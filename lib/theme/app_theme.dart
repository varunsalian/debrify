import 'package:flutter/material.dart';

import '../widgets/detail/theme/detail_theme.dart';
import '../widgets/detail/theme/detail_themes.dart';
import 'app_motion.dart';
import 'app_shape.dart';
import 'app_type.dart';

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
  final DownloadsTokens downloads;
  final YoutubeTokens youtube;
  final PlaylistTokens playlist;
  final StremioTvTokens stremioTv;
  final DebrifyTvTokens debrifyTv;
  final IptvTokens iptv;
  final ShellTokens shell;

  /// The non-colour half of the look — corner scale, focus ring, elevation,
  /// texture. See `app_shape.dart` for why this is a SCALE and not five named
  /// radii.
  final ShapeTokens shape;

  /// Typography. Read only by `AppThemeAdapter.themed`; the legacy path keeps
  /// its verbatim construction.
  final TypeTokens type;

  /// Tempo. Sites resolve it through `AppMotion.of(context)`, never directly —
  /// reduced motion needs a context.
  final MotionTokens motion;

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
    required this.downloads,
    required this.youtube,
    required this.playlist,
    required this.stremioTv,
    required this.debrifyTv,
    required this.iptv,
    required this.shell,
    required this.shape,
    required this.type,
    required this.motion,
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

    // Downloads' banner second stop. Hoisted because it is used BOTH as the
    // gradient's stop and as a fill that onAccent is scored against — the two
    // drifted once already, which silently voided the contrast guarantee.
    final downloadsAccent2 = _hueShifted(core.accent, 19);

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
      // The non-colour half. All three derive from the SAME core the colours
      // do, so a theme cannot end up with one palette's shape and another's
      // ink — and all three are pure functions of it, so they cost nothing
      // beyond the memoized derivation the controller already does.
      shape: ShapeTokens.fromDetail(core),
      type: TypeTokens.fromDetail(core),
      motion: MotionTokens.fromDetail(core),
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
      downloads: DownloadsTokens(
        // Downloads' slate ramp re-derived from the theme's own ground: each
        // role keeps its RELATIONSHIP to the page (a step off it, a step
        // toward the ink) rather than its legacy hue, so a theme with a warm
        // or light ground gets a coherent surface instead of stranded slate.
        fieldFill: mix(ground, tx, 0.04),
        previewCard: mix(ground, tx, 0.06),
        line: line,
        chipBorder: line,
        metaIcon: core.tx.withValues(alpha: 0.62),
        // The action colour follows the theme accent; legacy's indigo is a
        // legacy value, not a Downloads constant.
        accent: core.accent,
        // The banner gradient's second stop. NOT `core.state`: that is a
        // MEANING colour (progress, status), so borrowing it makes Phosphor's
        // banner run amber→green and Noir's white→red. Legacy's pair is
        // indigo→violet — a hue rotation at the same lightness — so derive
        // that RELATIONSHIP from whatever accent the theme has.
        accent2: downloadsAccent2,
        addAccent: core.accent,
        // Ink on a filled accent, chosen by CONTRAST rather than by whether
        // the page is light. `light ? ground : core.tx` was wrong: it gives
        // white on Noir's and Frost's near-white accents and amber on
        // Phosphor's amber — 1:1, invisible.
        //
        // The banner is a gradient, so the ink has to survive BOTH stops;
        // score the worse one. Same threshold and tie-break as `inkOn`, which
        // cannot be called here because it is an instance method and the
        // instance does not exist yet.
        // Scored against the two stops the banner ACTUALLY paints — accent
        // and accent2. It previously scored core.state, which stopped being
        // one of them when accent2 became a hue rotation, so the "survives
        // both stops" guarantee was checking a colour that is not on screen.
        onAccent: _inkOnWorstOf(core.accent, downloadsAccent2, core.tx, ground),
        shimmerBase: panel2,
        shimmerHighlight: mix(panel2, tx, 0.06),
      ),
      youtube: YoutubeTokens(
        // The cursor follows the theme's FOCUS colour. Legacy paints it and
        // `seeAll.accent` the same violet, which is a property of one palette,
        // not of the role.
        focus: core.focus,
        // Ink on a solid focus swatch. One fill, not two — `_inkOnWorstOf`
        // is the shared rule and `inkOn` is an instance method that does not
        // exist yet here, so the same fill is passed twice rather than
        // duplicating the threshold and tie-break.
        onFocus: _inkOnWorstOf(core.focus, core.focus, tx, ground),
        // A raised panel at the app's usual first elevation step, kept just
        // short of opaque the way the literal it replaces was.
        keyboardPanel: panel.withValues(alpha: 0.94),
        textBody: tx.withValues(alpha: 0.8),
        textDim: tx.withValues(alpha: 0.5),
        textFaint: tx.withValues(alpha: 0.35),
      ),
      playlist: PlaylistTokens(
        // Poster fallbacks fall from the placeholder toward the page, so a
        // theme gets a coherent card instead of a stranded slate rectangle.
        posterFallbackDeep: ground,
        posterTileBg: mix(ground, tx, 0.14),
        noPosterBg: mix(ground, tx, 0.10),
        noPosterDeep: ground,
        // Legacy's slate-and-white-veil ladder re-derived from the theme's own
        // ground and ink: each role keeps its RELATIONSHIP to the page, so a
        // light theme gets a darkening veil where legacy had a white one
        // instead of a surface of invisible fills.
        card: mix(ground, tx, 0.07),
        fieldFill: mix(ground, tx, 0.04),
        // Keeps the sheet's slight translucency — what sits behind it is the
        // barrier, not the page.
        sheetPanel: mix(ground, tx, 0.08).withValues(alpha: 0.96),
        // The core already owns "opaque fill behind loading/failed artwork" and
        // every theme declares it, so this follows that rather than making a
        // second, quieter guess at the same thing.
        posterPlaceholder: core.placeholder,
        accent: core.accent,
        controlFill: tx.withValues(alpha: 0.15),
        rowFill: tx.withValues(alpha: 0.03),
        // The theme's hairline TRANSLUCENT, not the ground-flattened `line`:
        // these strokes are drawn on cards and over artwork, where a colour
        // baked against the page is the wrong one.
        hairline: core.hair,
        focusRing: core.focus,
        // The theme's "distinction" colour — a starred item, not a cursor and
        // not a status.
        favoriteAccent: core.award,
        ink2: tx.withValues(alpha: 0.70),
        ink3: tx.withValues(alpha: 0.50),
        statusWatched: success,
        progressPlayed: core.state,
        destructive: error,
        warning: warning,
      ),
      stremioTv: StremioTvTokens(
        // Translucent, not an opaque step off the ground: half of the tuner's
        // controls sit ON the backdrop, where a `mix(ground, tx, …)` fill would
        // be a bright plate over the artwork.
        surfaceFill: tx.withValues(alpha: 0.04),
        hairline: core.hair,
        // Page ink, not `core.focus`: the gold content cursor (`home.focus`) is
        // on screen at the same time on the dial, and two identical rings stop
        // telling the viewer which plane the remote is in.
        focusRing: tx.withValues(alpha: 0.9),
        // Black on every theme, by the `AppTheme.onGlass` rule — it exists to
        // make text legible over an arbitrary poster.
        glass: Colors.black.withValues(alpha: 0.55),
        progressTrack: tx.withValues(alpha: 0.12),
        progressFill: tx.withValues(alpha: 0.95),
        sheetBg: core.pane.withValues(alpha: 1),
        // Tones of the theme's own accent instead of legacy's eight unrelated
        // hues. The channel id hashes modulo the length, so a shorter ramp is
        // still a valid ident set — and this one is already proven distinct and
        // legible on both grounds by the calendar's contrast test.
        channelIdent: _accentRamp(core.accent, light: light),
        // Most capable tier first. `_accentRamp` runs AWAY from the ground, so
        // its loudest tone is last on a dark theme and first on a light one;
        // reversing only the dark case keeps 4K the loudest badge on both.
        qualityTier: (light
                ? _accentRamp(core.accent, light: light)
                : _accentRamp(core.accent, light: light).reversed)
            .take(5)
            .toList(growable: false),
        // The theme's own rating colour — this IS that role; only legacy's
        // amber differs from it.
        starAccent: core.rating,
        // "Green means on" is what the dot says, so it tracks the semantic
        // green (deepened on paper) rather than the theme accent.
        toggleOn: success,
        // The absence of a state: a muted step between page and ink.
        toggleOff: mix(ground, tx, 0.30),
        loaderAccent: core.accent,
        loaderAccent2: mix(core.accent, tx, 0.45),
        // The page pulled toward the action colour — what legacy's #201636 is
        // next to its #0D0B1A ground.
        // Tinted off BLACK, not off the page. The loader is a deliberate dark
        // cinematic plate — its Material, scrims and vignettes are all black
        // on every theme — so this is the radial's bright stop ON that plate.
        // Deriving it from `ground` made Broadsheet paint a pale centre under
        // white checklist ink: unreadable, and no longer "dark cinematic"
        // either. The theme reaches it through the ACCENT it is tinted with.
        loaderGround: mix(const Color(0xFF000000), core.accent, 0.18),
        loaderRailFar: mix(core.accent, tx, 0.62),
        // Scored against that plate rather than assumed white. It resolves to
        // tx on every shipped theme; the scoring is what stops a future
        // light-accent theme from reintroducing the bug above.
        loaderInk: _inkOnWorstOf(
          mix(const Color(0xFF000000), core.accent, 0.18),
          const Color(0xFF000000),
          tx,
          ground,
        ),
        // Scored against the one swatch it is painted on, the loader's step
        // dot. `inkOn` would be the natural call and cannot be used here: it is
        // an instance method and the instance does not exist yet.
        inkOnFill: _inkOnWorstOf(core.accent, core.accent, tx, ground),
      ),
      debrifyTv: DebrifyTvTokens(
        // The identity follows the theme; legacy's Netflix red is a legacy
        // value, not a property of the channel grid.
        accent: core.accent,
        // Matches what the ThemeData adapter gives `dialogTheme`, so a Debrify
        // TV dialog and a Material one read as the same surface.
        dialogBg: core.pane.withValues(alpha: 1),
        dialogDeep: ground,
        controlResting: mix(ground, tx, 0.05),
        noticeBg: panel2,
        cardBg: mix(ground, tx, 0.08),
        // A visible step, not a nudge: this ground difference is the whole
        // signal that the cursor is on a row.
        cardFocusBg: mix(ground, tx, 0.18),
        controlBg: mix(ground, tx, 0.04),
        // Translucent, so the lift works over the page, over a card and over
        // artwork — and stays a lift rather than a smear on a paper theme.
        fillStrong: tx.withValues(alpha: 0.15),
        fillWeak: tx.withValues(alpha: 0.10),
        hairline: line,
        focusRing: core.focus,
        // Converges with [focusRing] on every real theme. The two differ only
        // under legacy, which is the one place the cyan belongs.
        focusRingAlt: core.focus,
        textDim: tx.withValues(alpha: 0.70),
        textMeta: tx.withValues(alpha: 0.60),
        textFaint: tx.withValues(alpha: 0.54),
        // Deepened on paper for the reason the status trio is: this gold marks
        // state ON the ground, and #FFD700 reads ~1.2:1 against one.
        favorite: light ? const Color(0xFF8A6100) : const Color(0xFFFFD700),
      ),
      iptv: IptvTokens(
        railBg: mix(ground, tx, 0.03),
        railSelectionFill: core.accent.withValues(alpha: 0.16),
        // Scored against what the row ACTUALLY composites to: the selection
        // tint over the rail, not the bare rail.
        railFocusInk: _inkOnWorstOf(
          Color.alphaBlend(
            core.accent.withValues(alpha: 0.16),
            mix(ground, tx, 0.03),
          ),
          mix(ground, tx, 0.03),
          tx,
          ground,
        ),
        // The cockpit recedes rather than lifts, and "deeper than the page" is
        // directional — so it takes the theme's OWN recessed ground, which is
        // deeper than `ground` in all twenty themes. The same reasoning (and
        // the same source) as `shell.railInk`.
        stageBg: core.railBg,
        rowFocusFill: mix(ground, tx, 0.05),
        // Same step as `sheetSurface`; a separate field only because legacy
        // pins a different literal (see the doc comment).
        modalBg: mix(ground, tx, 0.08),
        // A mat for artwork that is NOT ours. IPTV logos are light marks on
        // transparency, so on a paper theme the plate goes dark instead of
        // tracking the page — expressed in the theme's own ink rather than a
        // hardcoded navy, so it stays that theme's black.
        logoPlate: light ? mix(ground, tx, 0.82) : mix(ground, tx, 0.09),
        chipSurface: mix(ground, tx, 0.08).withValues(alpha: 0.94),
        // Recessed relative to `modalBg`, not to the page — see the doc.
        fieldFill: mix(ground, tx, 0.02),
        // The surface line, one step firmer: a resting input border has to
        // read as an affordance, not as a divider.
        fieldBorder: mix(line, tx, 0.06),
        hairline: core.hair,
        surfaceTint: tx.withValues(alpha: 0.04),
        inkMid: tx.withValues(alpha: 0.70),
        inkDim: tx.withValues(alpha: 0.55),
        inkFaint: tx.withValues(alpha: 0.35),
        // Broadcast conventions, deepened on paper exactly like the status
        // trio above — never the theme accent, or a capture reads as a
        // selection and an on-air dot reads as chrome.
        recordAccent: light ? const Color(0xFFBE123C) : const Color(0xFFF43F5E),
        favoriteAccent: light
            ? const Color(0xFFBE123C)
            : const Color(0xFFF43F5E),
        liveDot: light ? const Color(0xFF0F7A55) : const Color(0xFF34D399),
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


/// [c] rotated [degrees] around the hue wheel, keeping saturation and
/// lightness. Used for decorative gradient pairs, where the second stop should
/// be "the accent, shifted" rather than a colour that already means something.
Color _hueShifted(Color c, double degrees) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withHue((hsl.hue + degrees) % 360).toColor();
}

/// Ink that stays legible on the worse of two fills.
///
/// Extracted rather than inlined because `AppTheme.inkOn` is an instance method
/// and `fromDetail` needs the same rule while the instance is still being
/// built. Keep the threshold and tie-break identical to `inkOn` — two rules for
/// "readable ink on a fill" would drift.
Color _inkOnWorstOf(Color a, Color b, Color tx, Color ground) {
  double ratio(Color ink, Color fill) {
    final li = ink.withValues(alpha: 1).computeLuminance();
    final lf = fill.withValues(alpha: 1).computeLuminance();
    final hi = li > lf ? li : lf;
    final lo = li > lf ? lf : li;
    return (hi + 0.05) / (lo + 0.05);
  }

  double worst(Color ink) {
    final ra = ratio(ink, a);
    final rb = ratio(ink, b);
    return ra < rb ? ra : rb;
  }

  const adequate = 4.0;
  if (worst(tx) >= adequate) return tx;
  return worst(ground) > worst(tx) ? ground : tx;
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
/// Downloads' palette.
///
/// The one surface that is not painted in the app's purple: it uses a Tailwind
/// SLATE ramp (`#0B1220 → #111827 → #1E293B → #334155 → #475569 → #94A3B8`)
/// with an INDIGO action colour, and legacy must keep exactly that. A real
/// theme re-derives the same roles from its own ground and accent, so the
/// slate/indigo identity is a property of legacy, not of the surface.
///
/// Roles that already existed elsewhere at the identical value are NOT
/// duplicated here — the sheet ground is `settings.sheetBg`, the slate
/// hairline and chip fill are `home.controlBg`, the raised pill is
/// `cloud.dialogSurface`, the Add-pill green is `cloud.statusSuccess`, and the
/// keyboard highlight is `settings.accent`. Re-declaring them would let the
/// two copies drift.
class DownloadsTokens {
  /// Filled ground of the Add sheet's URL and filename fields.
  final Color fieldFill;

  /// Translucent ground of the URL preview card.
  final Color previewCard;

  /// Hairline stroke: outlined-button side, input border, chip and
  /// preview-card outline.
  ///
  /// NOT `home.controlBg`, though legacy paints both `#334155`. That role is a
  /// filled control ground and derives as a 0.20 step off the page; borrowing
  /// it would turn every Downloads hairline into a bright stroke on any theme
  /// that lifts it. A line is a line — it derives like the other line tokens.
  final Color line;

  /// The `_StatChip` pill outline — one slate step above the fill.
  final Color chipBorder;

  /// Muted slate glyph inside chips and the preview row.
  final Color metaIcon;

  /// The primary action colour, and the violet it gradients into on the two
  /// sheet header banners.
  final Color accent;
  final Color accent2;

  /// Ink and glyphs sitting ON a filled accent.
  final Color onAccent;

  /// The Add-download pill's identity: border, focus glow, icon and label.
  ///
  /// NOT `cloud.statusSuccess`, though legacy paints both `#10B981`. This is a
  /// control's identity, not a status — a theme is entitled to move "success"
  /// without repainting the Add button.
  final Color addAccent;

  /// Loading-skeleton pair: the resting fill and the travelling highlight.
  final Color shimmerBase;
  final Color shimmerHighlight;

  const DownloadsTokens({
    required this.fieldFill,
    required this.previewCard,
    required this.line,
    required this.chipBorder,
    required this.addAccent,
    required this.metaIcon,
    required this.accent,
    required this.accent2,
    required this.onAccent,
    required this.shimmerBase,
    required this.shimmerHighlight,
  });
}

/// The Browse tab's YouTube source: the search shell it raises the in-app TV
/// keyboard from, and the video grid's own ink ladder.
///
/// Deliberately small — six fields — because most of what this surface paints
/// already belongs to somebody else's role and is READ rather than
/// re-declared. The page ground and the content accent are `seeAll.bg` /
/// `seeAll.accent` (the screen literally imports `kSeeAllBg` and
/// `kSeeAllAccent`); the battery-exemption sheet the download path raises is
/// Downloads' own surface, so it reads `settings.sheetBg`, `downloads.line`
/// and the `downloads.accent`/`accent2` pair its banner already names; and
/// full-strength panel ink is just `core.tx`.
///
/// Three things stay OUT of this profile on principle rather than by
/// oversight:
///
/// * **Glass and shadow.** The scrims over a thumbnail (duration pill 0.82,
///   hover wash 0.28, play disc 0.45) and the card's drop shadow stay literal
///   black. They exist to make content legible over an ARBITRARY image, so
///   they cannot follow the page — that is the premise [AppTheme.onGlass]
///   is built on, and the derived adapter likewise pins `colorScheme.shadow`
///   to black on light themes.
/// * **The channel monogram.** `brandAccentFor()` hashes a channel name to a
///   fixed-saturation swatch that is identical on every theme, so its white
///   letter is fixed too. Contrast-checking ink against a fill that never
///   moves would flip today's white to near-black and buy nothing.
/// * **The card's title, author and thumbnail placeholder.** Never literals:
///   they read `textTheme`, `onSurfaceVariant` and `surfaceContainerHigh`,
///   and have always followed `ThemeData` — which the adapter derives.
@immutable
class YoutubeTokens {
  /// The DPAD cursor: the video card's active border and the accent glow
  /// beneath it, the search field's shell ring, and — through
  /// `TvTextField.accent`, which feeds `TvKeyboardPanel.accent` — the
  /// highlighted keycap, the latched shift and the dictation mic.
  ///
  /// NOT `seeAll.accent`, though legacy paints both `#7B5CFF`. "Where am I"
  /// and "what is this app" are different questions, and every subprofile
  /// carrying both keeps them apart (`home.chromeAccent` vs `home.focus`,
  /// `shell.navAccent` vs `shell.navFocus`). Merging them would forfeit
  /// `core.focus` on all 20 themes to preserve one palette's coincidence —
  /// and the surface still reads `seeAll.accent` for the things that really
  /// are accent: the spinners, the Retry fill, the empty-state glyph.
  final Color focus;

  /// Ink and glyphs sitting ON a solid [focus] fill — the highlighted keycap's
  /// label and the dictation mic disc, the panel's only two opaque swatches.
  ///
  /// Contrast-chosen, not `core.tx`: Noir, Obsidian, Halo and Frost focus on
  /// white, Vault on bone, Broadcast on yellow and Verdant on lime, and a
  /// hardcoded white label is invisible on every one of them. The panel's
  /// TRANSLUCENT accent washes (the notice bar at 0.18, the mic halo at 0.22)
  /// carry ordinary ink instead and are not this role.
  final Color onFocus;

  /// The in-app TV keyboard's floating ground — held just short of opaque so
  /// the field behind it stays faintly readable.
  ///
  /// NOT `settings.panel`, though the literal's own source comment calls it
  /// "settings-panel purple": it is a different hue at 0.94 alpha, and that
  /// comment is exactly the sort of thing that would justify a wrong reuse.
  /// It is a raised panel by ROLE, so it derives like one.
  final Color keyboardPanel;

  /// Body copy on the page — the search error message.
  ///
  /// The three rungs below are tokens rather than call-site alphas for the
  /// same reason `settings.dim`/`dim2` are: this surface strikes ink at eight
  /// different alphas across four files with no constant module of its own,
  /// and a named ladder is what stops the next edit inventing a ninth. Not
  /// `core.tx2`/`tx3` — those sit at 0.64 and 0.40 while legacy's rungs are
  /// 0.8 / 0.5 / 0.35, so borrowing them would move pixels. Sites that sit
  /// slightly off a rung strike their alpha from the nearest one with
  /// [AppTheme.fade], so the hierarchy survives on every theme.
  final Color textBody;

  /// Supporting copy: the result count, the quality-ceiling hint, the
  /// empty-state subtitle, the clear glyph.
  final Color textDim;

  /// The weakest rung: the empty-state glyph and the info icon beside the
  /// quality hint — present, but never competing with a thumbnail.
  final Color textFaint;

  const YoutubeTokens({
    required this.focus,
    required this.onFocus,
    required this.keyboardPanel,
    required this.textBody,
    required this.textDim,
    required this.textFaint,
  });
}

/// Playlist: the library screen, the content view's file browser and episode
/// list, the playlist action sheet, and the seven "Preparing playlist…" dialogs
/// `playlist_player_service` pushes from static methods.
///
/// Legacy's identity here is Tailwind SLATE under a white-at-alpha ladder — one
/// literal (`#1E293B`) doing three different jobs, and 0.03 / 0.10 / 0.15 / 0.30
/// white carrying every fill, line and cursor on the surface. A real theme
/// re-derives each role by its RELATIONSHIP to the page (a step off the ground,
/// a step toward the ink, the theme's own cursor and state colours), because a
/// white veil on a paper theme is not a dimmer veil — it is nothing at all.
///
/// Roles that already existed elsewhere at the identical value are NOT
/// duplicated here: the seven service dialogs, the season dropdown and the
/// refresh disc read `cloud.dialogSurface`; the two confirm dialogs and the
/// TVMaze search dialog read `home.sheetBg`; explicit white page ink reads
/// `core.tx`; and the shared `TvTextField` / `TvKeyboard` chrome keeps reading
/// `settings.accent`, as Downloads already established. The keyboard's own
/// panel ground stays with that widget for the same reason — it is reached from
/// Search, Settings and IPTV too, so Playlist is the wrong owner for it.
@immutable
class PlaylistTokens {
  /// Opaque ground of the file-browser and search-result row `Card`s, and of
  /// the empty-state icon disc at half alpha.
  ///
  /// NOT `cloud.dialogSurface`, though legacy paints both `#1E293B`. That role
  /// derives as `core.pane` — a MODAL ground — and these cards are the
  /// surface's dominant page element. Borrowing it would render a whole scroll
  /// of file rows as a stack of floating dialogs on any theme that separates
  /// the two.
  final Color card;

  /// Recessed fill behind the two search fields and the clear button beside
  /// them.
  ///
  /// Also not `cloud.dialogSurface`: an input well is a hole IN the page, not a
  /// surface floating over it, so it derives shallower than [card] instead of
  /// inheriting a modal's ground. Legacy spells all three the same colour; that
  /// is a legacy fact, not three-into-one permission.
  final Color fieldFill;

  /// The playlist action sheet's own panel.
  ///
  /// Near-opaque rather than opaque on purpose: TV paints it flat (a
  /// `BackdropFilter` re-rasterises for every frame of the sheet's slide, a
  /// full-screen `saveLayer` on weak GPUs) while phone and desktop paint a
  /// translucent step behind a real blur. One role, two paints — and the
  /// sheet's CONTENT inherits `ThemeData` text either way, which is why it
  /// cannot stay a dark literal.
  final Color sheetPanel;

  /// Fill behind a missing or still-loading poster / episode still.
  final Color posterPlaceholder;

  /// The surface's action colour: the page spinner, the refresh indicator, the
  /// All Items section icon, the TVMaze dialog's chrome.
  final Color accent;

  /// Raised control ground — the focused search toggle, a highlighted glass
  /// button, the play-overlay disc, the provider pill, the unwatched toggle.
  /// Several of these sit over artwork, so it steps toward the ink rather than
  /// staying a white scrim.
  final Color controlFill;

  /// The idle episode-card ground: present enough to lift the row off the page,
  /// faint enough that a list of them does not read as stripes. The focused
  /// state is this same veil lifted, so the two have to move together.
  final Color rowFill;

  /// Divider and idle-border stroke: the sheet divider, card and tile outlines,
  /// the count-badge edge, the unplayed part of a progress track.
  ///
  /// NOT [controlFill], even though the sheet happens to draw its own border at
  /// that alpha today. A line that derives like a filled control becomes a
  /// bright stroke the moment a theme lifts its controls. A line is a line.
  final Color hairline;

  /// The DPAD cursor. Legacy draws it as a dim white border — one of five
  /// different literals doing this job across the surface — which is invisible
  /// on a paper theme, so it follows the theme's own cursor colour rather than
  /// a fixed fraction of the ink.
  final Color focusRing;

  /// Favorites' identity: the section icon and its glow, the card's star badge,
  /// the action sheet's favourite row, and the section widget's own fallback.
  ///
  /// NOT a focus colour, though legacy's gold sits one step from
  /// `home.focus` — this marks what the USER chose, not where the cursor is,
  /// and a theme must be able to move one without the other.
  final Color favoriteAccent;

  /// The second and third ink tiers: supporting copy (file sizes, dialog body,
  /// Keep / Cancel labels) and metadata or hints (air dates, runtimes, plots,
  /// search hints, empty-state copy).
  ///
  /// NOT `core.tx2` / `core.tx3`, which sit at 0.64 and 0.40 — Playlist's
  /// shipped ladder is 0.70 and 0.50, and pinning it to the core's would
  /// repaint a hundred-odd strings under `legacy`. Only the TOP tier is shared:
  /// explicit white ink is `core.tx`, which Signal declares as literal white.
  final Color ink2;
  final Color ink3;

  /// Finished / watched: the DONE badge, the completed progress bar and its
  /// gradient. Ink inside the badge must come from `AppTheme.inkOn` — this fill
  /// deepens on a light theme, and a hardcoded white label goes with it.
  final Color statusWatched;

  /// The played portion of a progress bar and the in-progress percent badge.
  ///
  /// Playback STATE, which is why it derives from the theme's state colour and
  /// not from [accent]: the core already treats `state` as the progress role
  /// (`stateGradient` exists for exactly this). Legacy's Material blue is a
  /// leftover — the file browser paints this meaning blue while the OTT cards
  /// paint it indigo — and it is a separate token from the file-type icon tint
  /// it happens to share a value with.
  final Color progressPlayed;

  /// The Delete row's ink and glyph in the action sheet.
  ///
  /// NOT `calendar.accent`, and the trap is worth stating: the Remove confirm
  /// button paints this same meaning as `#E50914`, which is byte-identical to
  /// the calendar's Netflix red. That red means "the Trakt/Simkl schedule's
  /// identity", not "destructive", so the pin test's silence about it is not a
  /// semantic match.
  final Color destructive;

  /// The Fix Metadata chip (fill, border, icon and label) and the Clear
  /// Progress confirm button, which spells the identical colour as
  /// `Color(0xFFFF9800)` — one value, two spellings, so the two sites collapse
  /// onto this token without moving a pixel.
  final Color warning;

  /// The deep stop of a poster fallback — the loading/error gradient and the
  /// no-poster tile both fall from [posterPlaceholder] to this.
  ///
  /// A role rather than a call-site `isLegacy` branch: the branch preserved
  /// legacy correctly but left the fill unable to follow a theme, which is the
  /// exact job the token layer exists to do.
  final Color posterFallbackDeep;

  /// Ground of a small poster tile that has no artwork (the TVMaze picker's
  /// rows). Distinct from [posterPlaceholder]: legacy paints a neutral grey
  /// here and a blue-violet there.
  final Color posterTileBg;

  /// The no-artwork card's own gradient. A separate pair from the loading
  /// fallback above: legacy paints this one slate and that one near-black,
  /// and collapsing them would move one of the two.
  final Color noPosterBg;
  final Color noPosterDeep;

  const PlaylistTokens({
    required this.posterFallbackDeep,
    required this.posterTileBg,
    required this.noPosterBg,
    required this.noPosterDeep,
    required this.card,
    required this.fieldFill,
    required this.sheetPanel,
    required this.posterPlaceholder,
    required this.accent,
    required this.controlFill,
    required this.rowFill,
    required this.hairline,
    required this.focusRing,
    required this.favoriteAccent,
    required this.ink2,
    required this.ink3,
    required this.statusWatched,
    required this.progressPlayed,
    required this.destructive,
    required this.warning,
  });
}

/// The Stremio TV tuner: the Stage over a full-bleed backdrop, the dial of
/// channel cards, this surface's own sheets and filter page, and the play
/// loader that fronts every launch from it.
///
/// Two facts shape the set. Most of the surface is painted ON ARTWORK rather
/// than on the page, so its fills and strokes are ink- or black-at-alpha rather
/// than opaque steps off the ground — a card fill derived as
/// `mix(ground, tx, …)` would be a bright plate on top of a poster. And the
/// tuner carries TWO focus treatments on one screen (a white ring on chrome,
/// `home.focus`'s gold on content); that split is what tells a viewer which
/// plane the remote is in, so it survives as its own token.
///
/// Roles that already exist at the identical value are NOT re-declared here,
/// because two copies drift: the page ink and bloom are `home.bg` /
/// `home.wash`, the content cursor and its bloom are `home.focus` /
/// `home.focusDeep`, active chrome is `home.chromeAccent`, the LIVE indicator
/// is `home.highlight`, the missing-poster fill is `home.posterPlaceholder`,
/// the loading skeleton is `downloads.shimmerBase` / `downloads.shimmerHighlight`,
/// and the whole secondary-label ladder is `core.tx` at each call site's own
/// alpha — twenty alphas are a modulation of one role, not twenty roles.
@immutable
class StremioTvTokens {
  /// Resting fill of a raised control or card — header buttons, the UP NEXT
  /// chip, dialog item cards, skeleton tiles.
  ///
  /// NOT `calendar.line`, though legacy paints both `white @ 0.04`. That role
  /// is a GRID HAIRLINE and derives as `core.hair`; borrowing it would repaint
  /// every header button on any theme that darkens or thickens its hairlines.
  /// It is also why this and [hairline] are two tokens: this surface uses white
  /// at 0.04 AND at 0.06 as both a fill and a border, so the literals cross and
  /// only the roles tell them apart.
  final Color surfaceFill;

  /// Hairline borders around cards, pills and the dial shelf's top edge.
  ///
  /// Translucent for the same reason as [surfaceFill] — most are drawn over
  /// artwork, where a ground-derived line reads as a solid bar.
  final Color hairline;

  /// The 2px ring that says "the remote is here" on CHROME — header buttons,
  /// source-picker tabs, source rows.
  ///
  /// Deliberately not `home.focus`: the gold content cursor is on the dial at
  /// the same moment, and one colour for both would stop distinguishing the two
  /// planes. It follows page ink instead, so it inverts with the theme rather
  /// than staying a white ring on paper.
  final Color focusRing;

  /// The dark glass floating over artwork — Stage pills, the OPTIONS / GENRES
  /// hint chips, the dial card's title strip, the favourite bubble.
  ///
  /// Stays black on every theme, by the same rule as [AppTheme.onGlass]: it
  /// exists to make text legible over an arbitrary poster, so it cannot follow
  /// a light ground. Anything drawn on it takes `onGlass`, never `core.tx`.
  final Color glass;

  /// The Stage's broadcast progress bar: the unplayed track and the played
  /// fill.
  ///
  /// Page ink rather than glass ink, because the Stage is a stack of `home.bg`
  /// scrims over the backdrop and so follows the theme's ground. The dial
  /// card's copy of this bar is NOT these tokens — it sits on [glass] and takes
  /// `onGlass` at its own two alphas, which resolves to the same white it paints
  /// today.
  final Color progressTrack;
  final Color progressFill;

  /// Ground of this surface's own bottom sheets — quick actions, all-channels,
  /// read-more, the manual source picker.
  ///
  /// Its own token rather than `sheetSurface`, `home.sheetBg` or
  /// `settings.sheetBg`: all four are near-black under legacy and all four are
  /// DIFFERENT literals, so folding them would change what ships today.
  final Color sheetBg;

  /// Tones hashed per channel id — the CH badge, the dial card's accent, the
  /// poster placeholder tint, the UP NEXT label.
  ///
  /// A LIST, and its ORDER is the contract: the hash indexes it modulo its
  /// length, so a reorder silently recolours every channel. The LENGTH may
  /// differ between profiles for the same reason — legacy pins its eight, a
  /// real theme derives six from its own accent.
  final List<Color> channelIdent;

  /// The manual source picker's quality ladder, most capable first: 4K, 1080p,
  /// 720p, 480p, HD.
  ///
  /// Ordered by PROMINENCE, not by hue. Each tier is drawn as TEXT on a 15%
  /// wash of itself, so every tone has to read against the sheet and the top
  /// tier has to out-shout the bottom one; legacy's gold-to-grey run is one way
  /// to say that, not the only one. Indexed by tier, so the order is a contract
  /// like [channelIdent]'s.
  final List<Color> qualityTier;

  /// The favourite star and the IMDb rating star.
  ///
  /// A field even though `core.rating` is exactly this role: legacy paints
  /// `#FFC107` where Signal's rating is `#F5C518`, so reading `core.rating`
  /// directly would change today's app. It DERIVES from `core.rating` — the pin
  /// is the only thing that stays amber.
  final Color starAccent;

  /// The filter page's all-on and all-off states — the count and the state dot,
  /// and the switch pill's dead track.
  ///
  /// [toggleOn] is not `cloud.statusSuccess` or `settings.success`: a filter is
  /// a state, not a status, and legacy's three greens are three different
  /// literals anyway. It still derives from the theme's semantic green, because
  /// "green means on" is the whole message. [toggleOff] is the absence of a
  /// state — a muted step between page and ink, not a colour of its own.
  final Color toggleOn;
  final Color toggleOff;

  /// The play loader's accent — the top rail, the step icons and connectors,
  /// the poster and Cancel glows — and [loaderAccent2], its soft partner
  /// carrying the loader's subtitle and note text and the rail gradient's far
  /// stop.
  ///
  /// The overlay is shared with the Search/Home play path, so it is owned here
  /// once rather than re-declared by whichever surface happens to open it.
  final Color loaderAccent;
  final Color loaderAccent2;

  /// The loader's deep, accent-tinted ground: the backdrop radial's bright
  /// stop, which the TV scrim ladder and the desktop glass card darken away
  /// from.
  final Color loaderGround;

  /// The loader rail's far gradient stop, paired with [loaderAccent].
  final Color loaderRailFar;

  /// Ink on the loader. Scored against [loaderGround] rather than forced
  /// white: the ground follows the theme, so a pale one left white checklist
  /// text unreadable — "dark cinematic" stops being true the moment the
  /// backdrop is not dark.
  final Color loaderInk;

  /// Ink and glyphs sitting ON a filled swatch — the check inside the loader's
  /// completed-step dot.
  ///
  /// Never `core.tx`: half the shipped themes have light accents (Broadcast's
  /// yellow, Verdant's lime, Noir and Frost's white) where the near-black glyph
  /// is the readable one and a white one is invisible. Chosen by contrast
  /// against the swatch actually painted.
  final Color inkOnFill;

  const StremioTvTokens({
    required this.surfaceFill,
    required this.hairline,
    required this.focusRing,
    required this.glass,
    required this.progressTrack,
    required this.progressFill,
    required this.sheetBg,
    required this.channelIdent,
    required this.qualityTier,
    required this.starAccent,
    required this.toggleOn,
    required this.toggleOff,
    required this.loaderAccent,
    required this.loaderAccent2,
    required this.loaderGround,
    required this.loaderRailFar,
    required this.loaderInk,
    required this.inkOnFill,
  });
}

/// Debrify TV — the channel-surfing surface (`magic_tv_screen.dart` and the
/// five dialogs under `screens/debrify_tv/`).
///
/// A near-black card-and-cursor surface: every ground is a small step off an
/// almost-invisible page, and the DPAD ring is the only bright thing on it.
/// That SHAPE is what these tokens keep. Legacy's black-and-Netflix-red is a
/// legacy fact — the surface is not "the red screen", it is "a page, three
/// steps off it, and a cursor".
///
/// Roles that already exist elsewhere at the identical value are NOT
/// re-declared here: the page ink is `core.tx` (Signal's `tx` IS pure white),
/// ink on a filled swatch comes from [AppTheme.inkOn] rather than a second
/// pinned white, and the Import Channels dialog's slate ground is
/// `home.sheetBg`. Duplicating them would let the copies drift.
///
/// What deliberately stays literal: the three action tones that tell three
/// actions apart (edit blue, share green, import violet), the Community
/// dialog's eight category swatches, and the modal barrier — a scrim is black
/// at alpha on every theme, for the same reason [AppTheme.onGlass] exists.
@immutable
class DebrifyTvTokens {
  /// The surface's identity: CH badges, the Play / Save / Add fills, the
  /// switch thumb, the brand glyph and the header gradient's bright stop.
  ///
  /// NOT `calendar.accent`, though legacy paints both `#E50914`. Every surface
  /// carries its own accent (`home.chromeAccent`, `settings.accent`,
  /// `cloud.accent`) exactly so a theme can move one without repainting the
  /// others; the schedule's red and the channel grid's red are two identities
  /// that happen to have been drawn from the same tin.
  final Color accent;

  /// Ground for the surface's own dialogs — channel editor, quick play,
  /// channel options, progress — and for the settings panel it paints at 0.8.
  ///
  /// A token because their CONTENT is unstyled `Text`, so it inherits
  /// `ThemeData` ink: pinned dark, a light theme serves near-black text on a
  /// near-black card.
  final Color dialogBg;

  /// The SECOND dialog ground legacy runs: the cached-loading and
  /// channel-creation cards' gradient top, and the external-player notice.
  ///
  /// Kept apart from [dialogBg] rather than fused, because they are two looks
  /// in the shipped app and one token cannot pin two literals.
  final Color noticeBg;

  /// The deep stop of a dialog's gradient, under [noticeBg].
  final Color dialogDeep;

  /// A resting (unfocused) control ground inside a dialog — the "don't show
  /// again" row.
  final Color controlResting;

  /// Resting ground of a channel card, a settings row and the dropdown.
  final Color cardBg;

  /// The same row with the DPAD cursor on it.
  ///
  /// A STEP off [cardBg], not a colour — focus has to read as movement, so the
  /// two must never converge. That is precisely what borrowing another
  /// profile's dialog ground would have done (see [cardBg]'s sibling note in
  /// the surface brief: `cloud.dialogSurface` and `home.sheetBg` both derive to
  /// `core.pane`, so a focus fill taken from one lands on top of the other).
  final Color cardFocusBg;

  /// Resting fill of the round top-action buttons (Play / Search / Options) —
  /// barely lifted off the page, because that row reads as glyphs rather than
  /// buttons until something focuses it.
  final Color controlBg;

  /// …and the fill those buttons take when focused or active, which the search
  /// field's focused border shares.
  ///
  /// Translucent by ROLE, not by accident: it lifts whatever is behind it, so
  /// one value works over the page, over a card and over artwork alike — and
  /// on a paper theme it stays a lift instead of becoming a white smear.
  final Color fillStrong;

  /// The softer translucent fill: secondary buttons, icon circles, the
  /// spinner's hub.
  final Color fillWeak;

  /// Idle border on cards, panels, chips and rows.
  ///
  /// NOT [fillWeak], though legacy paints them within two hundredths of an
  /// alpha of each other. A line is a line: it derives off the theme's own
  /// hairline like every other line token, while a fill derives off the ink.
  final Color hairline;

  /// The house DPAD focus border — cards, switch rows, dialog buttons, the
  /// dropdown's focused edge.
  final Color focusRing;

  /// The Community Channels dialog's own focus grammar (3px border, 0.25 fill,
  /// 0.5 glow).
  ///
  /// A second field rather than a second use of [focusRing] because legacy
  /// really does run two focus colours, and folding them would repaint twelve
  /// sites in the shipped app. Real themes derive both from `core.focus` and so
  /// converge them — which is the point: the inconsistency is legacy's, and it
  /// does not propagate.
  final Color focusRingAlt;

  /// Body and secondary ink — subtitles, panel titles, status lines. The
  /// surface's dominant text tier by a wide margin.
  ///
  /// The ramp is the surface's OWN rather than `core.tx2`/`tx3`: legacy runs
  /// three tiers at 70/60/54% while the core's are 64/40%, so borrowing the
  /// core's would recolour every line of text on the screen.
  final Color textDim;

  /// Meta and helper ink — filter labels, size and compression lines, the
  /// dropdown's helper row.
  final Color textMeta;

  /// The faintest tier — hints, empty-state glyphs, the unchecked checkbox.
  final Color textFaint;

  /// The favourite marker: the star on a card, the Favorites header glyph and
  /// the favourite-toggle fill.
  ///
  /// A token, unlike the surface's other action colours, because this is the
  /// one that marks STATE on a surface instead of filling a button — and
  /// `#FFD700` on a paper theme's ground is about 1.2:1, an invisible star.
  /// Deepened on light grounds the way the app's status trio is.
  final Color favorite;

  const DebrifyTvTokens({
    required this.accent,
    required this.dialogBg,
    required this.noticeBg,
    required this.dialogDeep,
    required this.controlResting,
    required this.cardBg,
    required this.cardFocusBg,
    required this.controlBg,
    required this.fillStrong,
    required this.fillWeak,
    required this.hairline,
    required this.focusRing,
    required this.focusRingAlt,
    required this.textDim,
    required this.textMeta,
    required this.textFaint,
    required this.favorite,
  });
}

/// IPTV / live-TV chrome.
///
/// Scoped to the COMMAND CENTER paint path — the shipped default. The
/// `edition` and `console` looks already carry a fully extracted palette in
/// `IptvStyleTokens`, and every IPTV widget branches on the style FIRST, so
/// these tokens feed only the `IptvStyleTokens.of(style) == null` branch. That
/// branch is the one that was still literals; the styled branches must not
/// change, or `of(style) == null` stops meaning "the shipped paint".
///
/// Roles that already existed at the identical value are NOT duplicated here.
/// The page ground is `seeAll.bg`, the accent pair is `seeAll.accent` /
/// `accent2`, the elevated chip and dropdown ground is `seeAll.panel`, the
/// filter-chip border is `seeAll.line`, the DPAD cursor is `home.focus`, the
/// list dialogs' ground is the shared `sheetSurface`, and full-strength ink is
/// `core.tx` — Signal's `tx` IS pure white, so that borrow is byte-identical
/// under legacy rather than merely close. Re-declaring any of them would let
/// the two copies drift.
@immutable
class IptvTokens {
  /// The cockpit's RECESSED ground: the live-preview stage, the info slab
  /// beneath it, and the command rail beside it.
  ///
  /// Not a step off the page like a panel — it goes the other way, because a
  /// video picture wants a mat that sinks rather than lifts. "Deeper than the
  /// page" is directional and every theme already declares its own recessed
  /// ground, so this takes that instead of a hand-rolled darken, which would
  /// have LIGHTENED a paper theme's stage.
  final Color stageBg;

  /// Fill of the FOCUSED / active channel or schedule row.
  ///
  /// NOT `seeAll.panel`, even though this fill's preview-pinned variant is
  /// exactly `#17132E` today. That role is an elevated container ground; this
  /// is a transient TINT that appears and disappears under the cursor. A theme
  /// entitled to raise its panels must not thereby drag a bright band across
  /// a fifty-thousand-row channel list.
  final Color rowFocusFill;

  /// Ground of the IPTV dialogs and the schedule sheet.
  ///
  /// Derives the same way as the shared [AppTheme.sheetSurface] and stays a
  /// separate field for the same reason `cloud.menuSurface` does: legacy
  /// paints them different literals (`#14141D` vs `#141019`), and one token
  /// cannot pin both. The two list dialogs, whose literal IS `#141019`, read
  /// the shared token rather than this one.
  final Color modalBg;

  /// The mat behind a channel logo or a source monogram.
  ///
  /// Goes DARK on a light theme instead of tracking the page — the same
  /// reasoning as [AppTheme.onGlass]. The artwork on top is not ours: IPTV
  /// channel logos are overwhelmingly light marks on transparency, so a plate
  /// that followed a paper ground would erase most of a provider's lineup.
  final Color logoPlate;

  /// Ground of the floating status chip (catalog refresh, LIVE / TUNING).
  ///
  /// Nearly opaque on purpose: it floats over the page while rows scroll
  /// underneath, and a see-through chip there reads as a rendering fault. Its
  /// sibling that floats over LIVE VIDEO stays a black glass literal — that
  /// one exists to stay legible over an arbitrary picture, which is precisely
  /// the case that must not follow the theme.
  final Color chipSurface;

  /// Filled ground of the text fields inside the IPTV dialogs.
  ///
  /// Recessed relative to [modalBg] rather than to the page — a well sinks
  /// into the surface it was cut from. That relationship survives inversion:
  /// on a dark theme it lands under the dialog, on a paper theme it lands
  /// above it, which is what a white well on a grey sheet should do.
  final Color fieldFill;

  /// Those fields' resting border.
  ///
  /// Separate from [hairline] because it is an AFFORDANCE, not a division: an
  /// input has to look editable before it is focused, and legacy already draws
  /// it a full step firmer than any rule on the page.
  final Color fieldBorder;

  /// 1px borders, dividers, and the EPG progress-bar TRACK — the theme's own
  /// hairline, so IPTV rules move with every other surface's.
  final Color hairline;

  /// The faintest RAISED fill: the NOW row, a focused rail item, an inline
  /// notice.
  ///
  /// NOT `calendar.line`, though legacy paints both `white @ 4%`. That one is
  /// a grid rule and this is a wash under content; a theme that firms up its
  /// hairlines would otherwise start painting slabs behind every NOW row.
  final Color surfaceTint;

  /// The ink ramp below full strength: now-playing titles and programme
  /// descriptions, then sub-lines, counts and section captions, then the
  /// quietest tier — past programmes, hints and placeholders.
  ///
  /// Three levels rather than the two `settings.dim` / `dim2` carry, because
  /// this surface genuinely uses four: `IptvStyleTokens` already declares
  /// `fg` / `fgMid` / `fgDim` / `fgFaint` for the styled looks, and the
  /// Command palette is that same ramp left as literals. Full strength gets no
  /// field — it is `core.tx`. None of the three equals `settings.dim` (46%) or
  /// `dim2` (28%), so none of them can borrow those.
  final Color inkMid;
  final Color inkDim;
  final Color inkFaint;

  /// The DVR record signal: the capture dot, REC chips, the Record button.
  ///
  /// A light/dark pair like the status trio rather than a theme colour —
  /// "recording" is a broadcast convention, and letting it drift into a
  /// theme's accent would let a scheduled capture read as a selected row.
  /// Deepened on paper for the same reason `error` is.
  final Color recordAccent;

  /// The favourited mark: the heart on a channel row, and the Favorites list.
  ///
  /// NOT [recordAccent], though legacy paints both `#F43F5E`. One is a device
  /// state the user is watching for, the other is a saved preference — a theme
  /// must be able to move its REC signal without repainting every favourite.
  /// (`cloud.destructive` and `cloud.statusError` are kept apart on exactly
  /// this basis, and derive identically too.)
  final Color favoriteAccent;

  /// The on-air dot in a channel row and on the stage chip.
  ///
  /// Its own green rather than `cloud.statusSuccess`: legacy already paints
  /// them different emeralds (`#34D399` vs `#10B981`), and they mean different
  /// things — "on air" is a tally light, not a verdict that something
  /// succeeded. Deepened on paper so a 6px dot still reads.
  final Color liveDot;

  /// Command Center's rail ground. The styled layouts paint their own from
  /// `IptvStyleTokens`; this is the `tokens == null` path.
  final Color railBg;

  /// Ink on a FOCUSED Command Center rail row.
  ///
  /// Scored against the SELECTED row's composited fill, not the bare rail:
  /// the text sits on [railSelectionFill] over [railBg], and scoring the rail
  /// alone reports a contrast the user never sees.
  final Color railFocusInk;

  /// The selected Command Center rail row's tint, over [railBg].
  final Color railSelectionFill;

  const IptvTokens({
    required this.railBg,
    required this.railFocusInk,
    required this.railSelectionFill,
    required this.stageBg,
    required this.rowFocusFill,
    required this.modalBg,
    required this.logoPlate,
    required this.chipSurface,
    required this.fieldFill,
    required this.fieldBorder,
    required this.hairline,
    required this.surfaceTint,
    required this.inkMid,
    required this.inkDim,
    required this.inkFaint,
    required this.recordAccent,
    required this.favoriteAccent,
    required this.liveDot,
  });
}

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
    // Every one of these is a NO-OP by construction, which is what makes the
    // shape sweep safe: `scale: 1` means `shape.br(12)` IS
    // `BorderRadius.circular(12)`, a null family means Inter, and `scale: 1`
    // motion means the literal a site already had. Legacy cannot drift here
    // the way it can on a colour, because there is no legacy geometry token
    // to disagree with — only arithmetic identity.
    shape: ShapeTokens.legacy,
    type: TypeTokens.legacy,
    motion: MotionTokens.legacy,
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
      const Color(
        0xFF7B5CFF,
      ).withValues(alpha: 0.38),
      line: // kSeeAllLine
      const Color(
        0xFFB4A0FF,
      ).withValues(alpha: 0.12),
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
      const Color(
        0xFFB4A0FF,
      ).withValues(alpha: 0.12),
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
    downloads: DownloadsTokens(
      fieldFill: const Color(0xFF111827), // Add sheet URL/filename field
      previewCard: const Color(0x141E293B), // URL preview card ground
      line: const Color(0xFF334155), // hairlines (value-equal to controlBg)
      chipBorder: // _StatChip outline
      const Color(
        0xFF475569,
      ).withValues(alpha: 0.3),
      metaIcon: const Color(0xFF94A3B8), // chip + preview-row glyph
      accent: const Color(0xFF6366F1), // Downloads' action indigo
      accent2: const Color(0xFF8B5CF6), // banner gradient's violet stop
      addAccent: const Color(0xFF10B981), // Add pill identity (not "success")
      onAccent: Colors.white, // ink on a filled accent
      shimmerBase: const Color(0xFF223049), // skeleton resting fill
      shimmerHighlight: const Color(0xFF2A3A55), // skeleton travelling stop
    ),
    youtube: YoutubeTokens(
      focus: const Color(0xFF7B5CFF), // TvTextField.accent / card cursor
      onFocus: Colors.white, // TvKeyboardPanel.inkOnAccent default
      keyboardPanel: const Color(0xF01A1630), // TvKeyboardPanel._bg
      textBody: Colors.white.withValues(alpha: 0.8), // search error message
      textDim: Colors.white.withValues(alpha: 0.5), // counts + hints
      textFaint: Colors.white.withValues(alpha: 0.35), // empty-state glyph
    ),
    playlist: PlaylistTokens(
      posterFallbackDeep: const Color(0xFF06080F), // loading/error deep stop
      posterTileBg: const Color(0xFF333333), // TVMaze row, no artwork
      noPosterBg: const Color(0xFF1E293B), // no-poster card, near stop
      noPosterDeep: const Color(0xFF0F172A), // no-poster card, far stop
      card: const Color(0xFF1E293B), // file / search-result row Card
      fieldFill: const Color(0xFF1E293B), // search field + its clear button
      sheetPanel: const Color(0xF5181820), // action-sheet panel (TV paint)
      posterPlaceholder: const Color(0xFF1A1A2E), // no-poster gradient, top
      accent: const Color(0xFF6366F1), // spinner / refresh / section icon
      controlFill: Colors.white.withValues(alpha: 0.15), // raised control
      rowFill: Colors.white.withValues(alpha: 0.03), // idle episode card
      hairline: Colors.white.withValues(alpha: 0.1), // dividers + idle borders
      focusRing: Colors.white.withValues(alpha: 0.3), // DPAD cursor
      favoriteAccent: const Color(0xFFFFD700), // Favorites identity gold
      ink2: Colors.white70, // supporting copy
      ink3: Colors.white.withValues(alpha: 0.5), // metadata + hints
      statusWatched: const Color(0xFF059669), // DONE badge + finished bar
      progressPlayed: Colors.blue, // in-progress bar + percent badge
      destructive: const Color(0xFFFF6B6B), // action-sheet Delete row
      warning: Colors.orange, // Fix Metadata chip (== Color(0xFFFF9800))
    ),
    stremioTv: StremioTvTokens(
      // Composed the way the source composes them: `Color` stores alpha as a
      // double, so a hex pin like `0x0AFFFFFF` is NOT `withValues(alpha: 0.04)`.
      surfaceFill: Colors.white.withValues(alpha: 0.04), // card / control fill
      hairline: Colors.white.withValues(alpha: 0.06), // card + shelf borders
      focusRing: Colors.white.withValues(alpha: 0.9), // chrome DPAD ring
      glass: Colors.black.withValues(alpha: 0.55), // glass over artwork
      progressTrack: Colors.white.withValues(alpha: 0.12), // Stage bar, unplayed
      progressFill: Colors.white.withValues(alpha: 0.95), // Stage bar, played
      sheetBg: const Color(0xFF101015), // tuner bottom sheets
      channelIdent: const [
        // `_StremioTvTunerState._idents`, in order — the channel id hashes into
        // this list, so the ORDER is part of the contract, not just the set.
        Color(0xFF6C5CE7), // indigo
        Color(0xFFE84393), // magenta
        Color(0xFF00B894), // emerald
        Color(0xFFE17055), // coral
        Color(0xFF0984E3), // azure
        Color(0xFFFDCB6E), // amber
        Color(0xFF00CEC9), // teal
        Color(0xFFA29BFE), // lavender
      ],
      qualityTier: const [
        // `_qualityColor`'s switch, most capable first — the tier string
        // indexes this list, so the order is the contract here too.
        Color(0xFFFFD600), // 4K
        Color(0xFF536DFE), // 1080p
        Color(0xFF00BFA5), // 720p
        Color(0xFF78909C), // 480p
        Color(0xFF90A4AE), // HD
      ],
      starAccent: const Color(0xFFFFC107), // favourite + rating star
      toggleOn: const Color(0xFF34D399), // filter page _onColor
      toggleOff: const Color(0xFF4B465F), // filter page _offColor
      loaderAccent: const Color(0xFF8B6BFF), // PipelineLoadingOverlay.accent
      loaderAccent2: const Color(0xFFB9A6FF), // loader subtitle / note ink
      loaderGround: const Color(0xFF201636), // loader backdrop radial, bright stop
      loaderRailFar: const Color(0xFFC4B2FF), // loader top rail, far stop
      loaderInk: Colors.white, // loader ink on the dark backdrop
      inkOnFill: const Color(0xFF0A0712), // check glyph on the loader step dot
    ),
    debrifyTv: DebrifyTvTokens(
      accent: const Color(0xFFE50914), // CH badge / Play / Save fills
      dialogBg: const Color(0xFF0F0F0F), // magic_tv's five dialogs
      dialogDeep: const Color(0xFF101014), // dialog gradient, deep stop
      controlResting: const Color(0xFF141418), // "don't show again" row
      noticeBg: const Color(0xFF1B1B1F), // loading + creation + notice dialogs
      cardBg: const Color(0xFF1A1A1A), // resting card / settings row / dropdown
      cardFocusBg: const Color(0xFF2A2A2A), // the same row, focused
      controlBg: const Color(0xFF141414), // resting top-action button
      fillStrong: Colors.white.withValues(alpha: 0.15), // …focused or active
      // `Colors.white.withOpacity(0.1)` as the sources compose it. withOpacity
      // ROUNDS to an 8-bit alpha (26/255 = 0.1020), so a `withValues(alpha:
      // 0.1)` pin would be a DIFFERENT colour — the same precision trap the
      // calendar hairline documents. withAlpha says it exactly and without the
      // deprecation warning.
      fillWeak: Colors.white.withAlpha(26), // secondary button / icon circle
      hairline: Colors.white12, // idle border on cards, panels, chips, rows
      focusRing: Colors.white, // the house DPAD border
      focusRingAlt: const Color(0xFF00E5FF), // community dialog's cyan focus
      textDim: Colors.white70, // body and secondary ink
      textMeta: Colors.white60, // meta and helper text
      textFaint: Colors.white54, // hints and empty-state glyphs
      favorite: const Color(0xFFFFD700), // favourite star and toggle
    ),
    iptv: IptvTokens(
      railBg: const Color(0xFF080B18), // Command Center rail ground
      railSelectionFill: // selected rail row tint
          const Color(0xFF8A5CFF).withValues(alpha: 0.16),
      railFocusInk: const Color(0xFFE4DCFF), // ink on a focused rail row
      stageBg: const Color(0xFF0B0914), // live-preview stage + info slab
      rowFocusFill: const Color(0xFF141824), // focused channel / EPG row
      modalBg: const Color(0xFF14141D), // IPTV dialogs + schedule sheet
      logoPlate: const Color(0xFF1E2030), // channel-logo / monogram plate
      chipSurface: const Color(0xF0141225), // floating status chip
      fieldFill: const Color(0xFF0F0B14), // list-dialog text fields
      fieldBorder: const Color(0xFF2A2233), // those fields at rest
      // Composed the SAME way the sources compose them, for the reason the
      // calendar profile documents: Color stores alpha as a double now, so a
      // hex pin is a genuinely different value from `withValues(alpha:)`.
      hairline: Colors.white.withValues(alpha: 0.08), // borders, EPG track
      surfaceTint: Colors.white.withValues(alpha: 0.04), // NOW row, notices
      inkMid: Colors.white.withValues(alpha: 0.7), // now-playing, descriptions
      inkDim: Colors.white.withValues(alpha: 0.55), // sub-lines, counts
      inkFaint: Colors.white.withValues(alpha: 0.35), // past programmes, hints
      recordAccent: const Color(0xFFF43F5E), // DVR record signal
      favoriteAccent: const Color(0xFFF43F5E), // favourite mark (not "record")
      liveDot: const Color(0xFF34D399), // iptv_channel_row _liveDot
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
