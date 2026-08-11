import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_surface.dart' show SeparationModel;
import '../../../theme/theme_spec.dart' show inkOnFill;
import 'detail_themes.dart';

/// Which family a role uses. A theme names a ROLE, never a font, so it can
/// never ask for a face the platform doesn't have.
enum DetailFontRole { sans, serif, mono }

extension DetailFontRoleX on DetailFontRole {
  /// Null means "the platform default", which is what every Signal text style
  /// resolves to today — so Signal keeps its exact metrics.
  ///
  /// The two non-sans roles name BUNDLED faces rather than the CSS generics
  /// `serif`/`monospace` they used to. Three reasons, in order of weight:
  ///
  ///  * a generic family resolves to whatever the platform decides, so the
  ///    same theme was a different typeface on Android, on desktop and on the
  ///    Apple TV port — the exact opposite of a designed look;
  ///  * both faces are ALREADY in the bundle for the IPTV premium styles
  ///    (`pubspec.yaml`), so this costs no download and no APK growth;
  ///  * promoting type app-wide (`theme/app_type.dart`) makes the difference
  ///    visible on every screen rather than one, which is precisely when
  ///    "whatever the platform decides" stops being acceptable.
  ///
  /// **Why Fraunces and not Source Serif**, which the picker also names:
  /// `assets/fonts/SourceSerifPro-Regular.ttf` and `Merriweather-Regular.ttf`
  /// are not fonts. Both files — and both Roboto faces — are HTML error pages
  /// saved with a `.ttf` extension (they begin `<!DOCTYPE html>`), so anything
  /// asking for them silently falls back to the platform default. That is a
  /// pre-existing bug with its own blast radius (the subtitle font picker
  /// offers all three), and replacing them means adding megabytes of variable
  /// font to the bundle — a size decision, not a theming one. Fraunces is
  /// real, licensed (`assets/fonts/licenses/OFL-Fraunces.txt`) and already
  /// shipping, so the theme layer uses what actually exists.
  ///
  /// `sans` stays null, so **Signal — the shipped look — does not move**, and
  /// neither does any site that resolves to it.
  String? get family => switch (this) {
    DetailFontRole.sans => null,
    DetailFontRole.serif => 'Fraunces72',
    DetailFontRole.mono => 'JetBrainsMono',
  };

  /// Genuinely a fallback now: the named face is bundled and real, so these
  /// only matter if an asset fails to load. Deliberately does NOT list
  /// Merriweather or Source Serif — see the note above.
  List<String>? get fallback => switch (this) {
    DetailFontRole.sans => null,
    DetailFontRole.serif => const ['Georgia', 'Times New Roman', 'serif'],
    DetailFontRole.mono => const [
      'FiraMono',
      'Menlo',
      'Courier New',
      'monospace',
    ],
  };
}

/// The visual language of a details-page layout.
///
/// Colour is split into SIX roles rather than the two the app had, because
/// folding them together is what made every layout look the same:
///
/// * [accent] — identity. May be the artwork's own colour (see [useArtworkAccent]).
/// * [state] — a measurement: watched, progress, bound sources.
/// * [callout] — an attention flag, not a measurement: UP NEXT, CONTINUE WATCHING.
/// * [award] — immutable metadata worth highlighting.
/// * [rating] — data. Today this is IMDb yellow, which is NOT the state gold.
/// * [focus] — the DPAD cursor, and nothing else.
///
/// A theme may collapse them (Signal sets state/callout/award to one gold, so
/// Signal is unchanged) but the layouts must always ask for the right one.
///
/// Themes are `const` singletons from [DetailThemes]; equality is therefore
/// identity, which is what makes [DetailThemeScope.updateShouldNotify] correct
/// without hand-maintaining `==` over fifty fields.
@immutable
class DetailTheme {
  final String id;
  final String label;
  final String subtitle;

  // ── Grounds ───────────────────────────────────────────────────────────────
  final Color ground;
  final Color pane;
  final Color railBg;
  final Color panel;
  final Color hair;

  /// Opaque fill behind loading/failed artwork.
  ///
  /// Must NOT be translucent like [panel]: an image block sits over artwork and
  /// a see-through placeholder reads as a rendering fault rather than a
  /// pending image. Defaults to [pane], which is opaque in every theme.
  final Color? imageBg;

  /// Per-region light. Null is flat — most themes.
  final Gradient? paneWash;
  final Gradient? railWash;
  final Gradient? idWash;

  /// The body paints [ground] opaquely over the shell's tint. Light themes only.
  final bool lightGround;

  // ── Text ──────────────────────────────────────────────────────────────────
  final Color tx;
  final Color tx2;
  final Color tx3;

  // ── Meaning ───────────────────────────────────────────────────────────────
  final Color accent;
  final Color state;
  final Gradient? stateGradient; // Spectrum's progress bar only.
  final Color callout;
  final Color calloutText;
  final Color award;
  final Color rating;
  final Color focus;

  /// Signal keeps the poster-extracted accent. A fixed-palette theme (Noir's
  /// white, Phosphor's amber) must not be contaminated by the artwork.
  final bool useArtworkAccent;

  /// Opacity of the shell's per-title wash. 0 for fixed-palette themes.
  final double washOpacity;

  // ── Shape ─────────────────────────────────────────────────────────────────
  final double radius;
  final double radiusSm;
  final double radiusBtn;
  final double radiusImg;
  final double radiusCast;

  // ── Type ──────────────────────────────────────────────────────────────────
  final DetailFontRole displayFont;
  final DetailFontRole bodyFont;

  /// Drives eyebrows, meta, episode data, slabs and severity badges — the
  /// mock's `--f-data`. Independent of body: Graphite is sans with mono data.
  final DetailFontRole dataFont;

  /// Null means "the site decides".
  ///
  /// A 15px rail title and a 20px hero title are different things, and most
  /// themes have no business flattening them to one weight. A theme sets these
  /// only when its identity depends on them — Broadsheet's serif, Phosphor's
  /// wide mono caps. Signal sets neither, so Signal titles are unchanged.
  final FontWeight? displayWeight;
  final double? displayTracking;

  final bool displayUpper;

  /// The theme's display size, read as a SCALE against Signal's 23 — every
  /// site size was tuned against that, so scaling preserves the hierarchy
  /// instead of overwriting it.
  final double displaySize;

  final double slabSize;
  final double slabTracking;
  final FontWeight slabWeight;

  // ── Controls ──────────────────────────────────────────────────────────────
  final Color btnFill;
  final Color btnText;
  final FontWeight btnWeight;
  final Gradient? btnGradient;
  final Color? btnBorder;
  final double btnBorderWidth;

  final Color ghostFill;
  final Color ghostBorder;
  final Color ghostText;

  // ── Focus + surface ───────────────────────────────────────────────────────
  final double focusWidth;

  /// Signal draws the ring IN BOUNDS (a foreground border). The mock's outward
  /// offset is a per-theme choice, never Signal's.
  final double focusOffset;

  final List<BoxShadow> shadow;
  final Gradient? dividerGradient;

  /// 0 = off. Always 0 on TV — a blend-mode layer is a per-frame saveLayer.
  final double grain;

  /// Blueprint's 32px rule overlay.
  final bool grid;

  const DetailTheme({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.ground,
    required this.pane,
    required this.railBg,
    required this.panel,
    required this.hair,
    required this.tx,
    required this.tx2,
    required this.tx3,
    required this.accent,
    required this.state,
    required this.callout,
    required this.calloutText,
    required this.award,
    required this.rating,
    required this.focus,
    required this.btnFill,
    required this.btnText,
    required this.ghostFill,
    required this.ghostBorder,
    required this.ghostText,
    this.imageBg,
    this.paneWash,
    this.railWash,
    this.idWash,
    this.lightGround = false,
    this.stateGradient,
    this.useArtworkAccent = false,
    this.washOpacity = 0,
    this.radius = 10,
    this.radiusSm = 6,
    this.radiusBtn = 999,
    this.radiusImg = 7,
    this.radiusCast = 999,
    this.displayFont = DetailFontRole.sans,
    this.bodyFont = DetailFontRole.sans,
    this.dataFont = DetailFontRole.mono,
    this.displayWeight,
    this.displayUpper = false,
    this.displayTracking,
    this.displaySize = 23,
    this.slabSize = 10.5,
    this.slabTracking = 1.5,
    this.slabWeight = FontWeight.w800,
    this.btnWeight = FontWeight.w700,
    this.btnGradient,
    this.btnBorder,
    this.btnBorderWidth = 1,
    this.focusWidth = 2.5,
    this.focusOffset = 0,
    this.shadow = const [],
    this.dividerGradient,
    this.grain = 0,
    this.grid = false,
  });

  // ── Rules a theme cannot break ────────────────────────────────────────────

  /// The cursor must survive at three metres whatever the theme asked for.
  /// Vault and Cinemascope both ask for 1px, which is invisible on a TV.
  double focusWidthFor(bool isTv) =>
      isTv ? math.max(focusWidth, 2.5) : focusWidth;

  /// Grain is a `BlendMode.overlay` layer — a per-frame saveLayer.
  double grainFor(bool isTv) => isTv ? 0 : grain;

  /// Aurora's 40px, Deep Field's 30px and Frost's 44px blur shadows re-raster
  /// on every focus move. On TV only cheap, near-hard shadows survive.
  List<BoxShadow> shadowFor(bool isTv) => isTv
      ? [
          for (final s in shadow)
            if (s.blurRadius <= 6) s,
        ]
      : shadow;

  /// The cursor colour to use ON a given surface.
  ///
  /// A theme picks one focus colour for the whole page, but the primary button
  /// is filled — and Noir's white cursor on its white button, Broadcast's
  /// yellow on yellow, Phosphor's amber on amber are all cursors you cannot
  /// see. Where the ring would disappear into what it sits on, fall back to the
  /// surface's own opposite, which is guaranteed to contrast with it.
  Color focusOn(Color surface) {
    final a = focus.computeLuminance();
    final b = surface.computeLuminance();
    final ratio = (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
    if (ratio >= 1.6) return focus;
    return b > 0.5 ? ground : tx;
  }

  // ── Convenience ───────────────────────────────────────────────────────────

  Color get placeholder => imageBg ?? pane;

  /// Scales a token's OWN alpha.
  ///
  /// `withValues(alpha:)` REPLACES it, which turns a 7% panel into a 40% one —
  /// and inverts the intent on a light theme, whose panel is black.
  Color fade(Color c, double factor) =>
      c.withValues(alpha: (c.a * factor).clamp(0.0, 1.0));

  BorderRadius get brRadius => BorderRadius.circular(radius);
  BorderRadius get brSm => BorderRadius.circular(radiusSm);
  BorderRadius get brBtn => BorderRadius.circular(radiusBtn);
  BorderRadius get brImg => BorderRadius.circular(radiusImg);
  BorderRadius get brCast => BorderRadius.circular(radiusCast);

  /// A SITE's own artwork radius, scaled by the theme.
  ///
  /// Posters, stills and portraits were each drawn at their own radius against
  /// Signal's 8px artwork. Scaling preserves that hierarchy — Signal is exact,
  /// and a square-cornered theme flattens every one of them together.
  BorderRadius imgRadius(double site) =>
      BorderRadius.circular(site * radiusImg / 8);

  /// Signal's 23px display is the baseline every site size was tuned against.
  double get displayScale => displaySize / 23;

  /// The display face at a SITE's own size.
  ///
  /// The site owns hierarchy; the theme owns family, case, colour and overall
  /// scale, and overrides weight/tracking only when it has declared them.
  TextStyle titleStyle({
    required double size,
    required FontWeight weight,
    required double tracking,
    double height = 1.05,
  }) => TextStyle(
    fontFamily: displayFont.family,
    fontFamilyFallback: displayFont.fallback,
    fontSize: size * displayScale,
    fontWeight: displayWeight ?? weight,
    letterSpacing: displayTracking ?? tracking,
    height: height,
    color: tx,
  );

  /// Broadsheet and Phosphor set titles in caps; most themes don't.
  String displayCase(String s) => displayUpper ? s.toUpperCase() : s;

  /// This theme with its text tokens replaced — the ONLY mutation the app-level
  /// text-brightness resolver needs. Deliberately not a general `copyWith`:
  /// fifty-odd optional parameters invite drive-by theme edits that bypass the
  /// registry, and nothing else has a legitimate reason to derive a theme.
  /// This theme with its text tokens replaced — the ONLY mutation the app-level
  /// text-brightness resolver needs.
  ///
  /// The legibility floor is re-applied HERE as well as in [withTokens],
  /// because this runs LAST. The preset blends text toward the ground, so a
  /// pair that cleared 3:1 when it was chosen can fall under it once Dim is
  /// applied — and a floor that the final step can undo is not a floor.
  DetailTheme withText({Color? tx, Color? tx2, Color? tx3}) {
    final wanted = tx ?? this.tx;
    final safe = _readable(wanted, [ground, pane]);
    final dimmed = safe != wanted;
    return _withTextRaw(
      tx: safe,
      // If the primary had to be pulled back, the tones derived from it are
      // rebuilt rather than kept — they were computed from the value that
      // failed.
      tx2: dimmed ? safe.withValues(alpha: 0.64) : tx2,
      tx3: dimmed ? safe.withValues(alpha: 0.40) : tx3,
    );
  }

  DetailTheme _withTextRaw({Color? tx, Color? tx2, Color? tx3}) => DetailTheme(
    id: id,
    label: label,
    subtitle: subtitle,
    ground: ground,
    pane: pane,
    railBg: railBg,
    panel: panel,
    hair: hair,
    tx: tx ?? this.tx,
    tx2: tx2 ?? this.tx2,
    tx3: tx3 ?? this.tx3,
    accent: accent,
    state: state,
    callout: callout,
    calloutText: calloutText,
    award: award,
    rating: rating,
    focus: focus,
    btnFill: btnFill,
    btnText: btnText,
    ghostFill: ghostFill,
    ghostBorder: ghostBorder,
    ghostText: ghostText,
    imageBg: imageBg,
    paneWash: paneWash,
    railWash: railWash,
    idWash: idWash,
    lightGround: lightGround,
    stateGradient: stateGradient,
    useArtworkAccent: useArtworkAccent,
    washOpacity: washOpacity,
    radius: radius,
    radiusSm: radiusSm,
    radiusBtn: radiusBtn,
    radiusImg: radiusImg,
    radiusCast: radiusCast,
    displayFont: displayFont,
    bodyFont: bodyFont,
    dataFont: dataFont,
    displayWeight: displayWeight,
    displayUpper: displayUpper,
    displayTracking: displayTracking,
    displaySize: displaySize,
    slabSize: slabSize,
    slabTracking: slabTracking,
    slabWeight: slabWeight,
    btnWeight: btnWeight,
    btnGradient: btnGradient,
    btnBorder: btnBorder,
    btnBorderWidth: btnBorderWidth,
    focusWidth: focusWidth,
    focusOffset: focusOffset,
    shadow: shadow,
    dividerGradient: dividerGradient,
    grain: grain,
    grid: grid,
  );

  /// The cursor colour: [wanted], else [authored], else a pole that reads.
  static Color _focusFor(Color wanted, Color authored, Color ground) {
    if (_contrast(wanted, ground) >= 2.0) return wanted;
    if (_contrast(authored, ground) >= 2.0) return authored;
    return _readable(wanted, [ground]);
  }

  /// [wanted] if it reads on every one of [surfaces]; otherwise whichever pole
  /// does. The floor is 3:1 — below that, text on a surface is decoration.
  static Color _readable(Color wanted, List<Color> surfaces) {
    double worst(Color c) => surfaces
        .map((s) => _contrast(c, s))
        .reduce((a, b) => a < b ? a : b);
    if (worst(wanted) >= 3.0) return wanted;
    const white = Color(0xFFFFFFFF);
    const black = Color(0xFF0E0E10);
    return worst(white) > worst(black) ? white : black;
  }

  /// WCAG-style contrast ratio between two opaque colours.
  static double _contrast(Color a, Color b) {
    final la = a.withValues(alpha: 1).computeLuminance();
    final lb = b.withValues(alpha: 1).computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Whether the primary button is FILLED with the accent, as opposed to the
  /// neutral ink recipe.
  ///
  /// A `ThemeSpec` records this as `accentButton`, but a registry theme carries
  /// only the resolved colours — so the authored fill is the one signal there
  /// is. Compared on the opaque value because a fill is never drawn
  /// translucent.
  bool get _btnIsAccent =>
      btnFill.withValues(alpha: 1) == accent.withValues(alpha: 1);

  /// This theme with user-chosen palette, shape and type values, and every
  /// field that DERIVES from them brought along.
  ///
  /// Narrow on purpose, exactly like [withText]: the registry stays the only
  /// place a theme is authored, and this is the one other legitimate mutation —
  /// a user editing tokens. It is emphatically not a general `copyWith`.
  ///
  /// The dependent fields are the whole reason this exists. Patching `ground`
  /// alone leaves `lightGround` claiming the opposite, and the detail layouts
  /// read that flag rather than the luminance — so a light ground would still
  /// render a dark page. Patching `callout` alone leaves `calloutText` at a
  /// contrast that was computed against the old swatch. Patching `state` leaves
  /// `stateGradient` painting the colour you just replaced.
  ///
  /// Radius follows the same relationships `ThemeSpec.toCore` uses, or the
  /// corners of one theme start disagreeing with each other.
  DetailTheme withTokens({
    Color? ground,
    Color? pane,
    Color? panel,
    Color? tx,
    Color? accent,
    Color? state,
    Color? callout,
    Color? focus,
    double? radius,
    double? pillRadius,
    DetailFontRole? displayFont,
    DetailFontRole? bodyFont,
    double? grain,
    double? washOpacity,
    bool? useArtworkAccent,
    SeparationModel? separation,
  }) {
    final g = ground ?? this.ground;
    // A FLOOR on legibility, and the one place this feature says no.
    //
    // Ground and ink are freely chosen, which means white-on-white is two taps
    // away — and the app that results cannot be navigated back out of, because
    // reaching the reset means reading the screens between here and it.
    // `kDetailThemesShipped` withholds two whole themes over exactly this.
    //
    // So hue is free and contrast is not: if the pair scores below 3:1, the ink
    // moves to whichever pole actually reads on that ground. It overrides an
    // explicit ink choice, deliberately — an unusable app is not a preference.
    // Surfaces have to share a POLARITY before ink can be judged against them.
    //
    // A white ground over Signal's near-black pane is unsatisfiable: black text
    // reads on the page and vanishes on every sheet. So an unedited pane
    // follows the ground it sits on — which is what a coherent theme does
    // anyway, and what `ThemeSpec` expresses as ground/sunken/raised being one
    // decision rather than three.
    // POLARITY IS ONE DECISION, and the ground makes it.
    //
    // Pane, fill and rail were separately editable, and the combinations were
    // unsatisfiable rather than merely ugly: a light page with a dark sheet has
    // no single ink that reads on both, and every fix for one broke the other.
    // Four free surfaces plus one ink is not a theme, it is four themes wearing
    // the same text.
    //
    // So the ground is chosen and everything under it follows — which is what
    // `ThemeSpec` already says by treating ground, sunken and raised as one
    // authored family. Hue stays free; polarity does not fork.
    final groundIsLight = g.computeLuminance() > 0.5;
    final pole = groundIsLight ? Colors.black : Colors.white;
    final resolvedPane =
        ground == null ? this.pane : Color.lerp(g, pole, 0.06)!;
    final resolvedRail =
        ground == null ? railBg : Color.lerp(g, pole, 0.02)!;

    // Against EVERY opaque surface the text sits on, not just the page: panes
    // and panels are independently editable, so checking the ground alone still
    // allows a white sheet carrying white text.
    final wantedInk = tx ?? this.tx;
    final ink = _readable(wantedInk, [g, resolvedPane]);
    final cal = callout ?? this.callout;
    final st = state ?? this.state;
    final r = radius ?? this.radius;
    final pill = pillRadius ?? radiusBtn;
    final inkEdited = ink != this.tx;
    final groundEdited = ground != null;
    final isLight = groundEdited ? g.computeLuminance() > 0.5 : lightGround;
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    // Every field below that is DERIVED from ink or ground has to move when
    // they do. The registry authored them together; editing one input and
    // keeping the rest is how you get a light theme wearing a dark theme's
    // panels, or a button whose label is the same colour as its fill.
    //
    // `ThemeSpec.toCore` is the rule being mirrored here, deliberately: two
    // derivations of the same field that disagree at the margins is worse than
    // one that is written twice.
    final derivedFromInk = inkEdited || groundEdited;
    return DetailTheme(
      id: id,
      label: label,
      subtitle: subtitle,
      ground: g,
      pane: resolvedPane,
      railBg: resolvedRail,
      // An explicit panel choice wins; otherwise it follows the ink it was
      // originally derived from.
      // Separation decides whether there are boxes at all, and the detail
      // widgets paint these fields directly — so a `space` look that still has
      // 7%-ink panels has not stopped having boxes, it has boxes the token
      // layer cannot see. Same rules as `ThemeSpec.toCore`.
      panel: panel ??
          (separation != null
              ? switch (separation) {
                  SeparationModel.space => const Color(0x00000000),
                  SeparationModel.rule => ink.withValues(alpha: 0.03),
                  SeparationModel.glass => ink.withValues(alpha: 0.10),
                  SeparationModel.fill => ink.withValues(alpha: 0.07),
                }
              : (inkEdited ? ink.withValues(alpha: 0.07) : this.panel)),
      hair: separation != null
          ? ink.withValues(
              alpha: separation == SeparationModel.rule ? 0.17 : 0.11)
          : (inkEdited ? ink.withValues(alpha: 0.11) : hair),
      tx: ink,
      // Derived from the ink at the alphas the registry itself uses, so an
      // edited ink carries its own secondary and tertiary tones instead of
      // leaving the old theme's showing through underneath it.
      // Keyed on the ENFORCED ink, not the requested one. A ground-only edit
      // that flips the primary text to the opposite pole must take the
      // secondary and tertiary tones with it, or a snow ground ends up with
      // black titles and translucent white metadata under them.
      tx2: inkEdited ? ink.withValues(alpha: 0.64) : tx2,
      tx3: inkEdited ? ink.withValues(alpha: 0.40) : tx3,
      accent: accent ?? this.accent,
      state: st,
      callout: cal,
      calloutText:
          callout == null && tx == null && ground == null
              ? calloutText
              : inkOnFill(cal, ink, g),
      award: award,
      rating: rating,
      // A cursor you cannot see is a television you cannot navigate. An
      // unreadable choice falls back to the theme's own focus colour rather
      // than to a pole — that one was authored to work here, and it is the same
      // rule an unrecognised swatch already follows.
      // A cursor you cannot see is a television you cannot navigate. The
      // chosen colour is preferred, the theme's own is the first fallback, and
      // a pole is the last — because on an edited ground the AUTHORED focus can
      // fail too (Signal's gold is 1.67:1 on snow).
      focus: _focusFor(focus ?? this.focus, this.focus, g),
      // The button pair keeps its ROLE.
      //
      // A theme whose primary button is filled with the accent must follow the
      // accent when that is edited, and must NOT be rewritten into the neutral
      // ink recipe just because the ground moved. A neutral button is the
      // reverse. Detecting the role from the authored fill is the only signal
      // available — a spec records it as `accentButton`, but a registry theme
      // does not carry the flag.
      //
      // Either way the label is SCORED against its own fill, so no edit can
      // leave text the same colour as the surface under it.
      btnFill: _btnIsAccent
          ? (accent ?? this.accent)
          : (derivedFromInk ? (isLight ? ink : mix(g, ink, 0.94)) : btnFill),
      btnText: _btnIsAccent
          ? ((accent != null || derivedFromInk)
              ? inkOnFill(accent ?? this.accent, ink, g)
              : btnText)
          : (derivedFromInk ? (isLight ? g : mix(ink, g, 0.94)) : btnText),
      // An authored gradient is a pair of colours chosen against the OLD fill;
      // there is no honest way to re-author it from one replacement. Dropped
      // when the fill it belonged to has moved.
      btnGradient:
          (_btnIsAccent && accent != null) || derivedFromInk ? null : btnGradient,
      ghostFill: separation != null
          ? switch (separation) {
              SeparationModel.space || SeparationModel.rule =>
                const Color(0x00000000),
              _ => ink.withValues(alpha: 0.10),
            }
          : (derivedFromInk ? ink.withValues(alpha: 0.10) : ghostFill),
      ghostBorder: separation != null
          ? ink.withValues(
              alpha: separation == SeparationModel.space ? 0.0 : 0.16)
          : (derivedFromInk ? ink.withValues(alpha: 0.16) : ghostBorder),
      ghostText: inkEdited ? ink : ghostText,
      imageBg: imageBg,
      paneWash: paneWash,
      railWash: railWash,
      idWash: idWash,
      // The layouts read this flag, not the luminance. Left stale, a light
      // ground renders a dark page.
      lightGround:
          ground == null ? lightGround : g.computeLuminance() > 0.5,
      // Dropped rather than recoloured when the state colour changes: the
      // gradient is an authored pair (Spectrum's progress bar), and there is no
      // honest way to re-author it from one replacement colour. A flat bar in
      // the new colour beats a gradient in the old one.
      stateGradient: state == null ? stateGradient : null,
      useArtworkAccent: useArtworkAccent ?? this.useArtworkAccent,
      washOpacity: washOpacity ?? this.washOpacity,
      radius: r,
      radiusSm: radius == null ? radiusSm : (r * 0.7).roundToDouble(),
      radiusBtn: pill,
      radiusImg: radius == null ? radiusImg : r,
      radiusCast: pillRadius == null ? radiusCast : pill,
      displayFont: displayFont ?? this.displayFont,
      bodyFont: bodyFont ?? this.bodyFont,
      dataFont: dataFont,
      displayWeight: displayWeight,
      displayUpper: displayUpper,
      displayTracking: displayTracking,
      displaySize: displaySize,
      slabSize: slabSize,
      slabTracking: slabTracking,
      slabWeight: slabWeight,
      btnWeight: btnWeight,
      btnBorder: btnBorder,
      btnBorderWidth: btnBorderWidth,
      focusWidth: focusWidth,
      focusOffset: focusOffset,
      shadow: shadow,
      dividerGradient: dividerGradient,
      grain: grain ?? this.grain,
      grid: grid,
    );
  }

  TextStyle get slabStyle => TextStyle(
    fontFamily: dataFont.family,
    fontFamilyFallback: dataFont.fallback,
    color: tx3,
    fontSize: slabSize,
    fontWeight: slabWeight,
    letterSpacing: slabTracking,
  );

  TextStyle dataStyle({
    double size = 11,
    Color? color,
    FontWeight weight = FontWeight.w600,
  }) => TextStyle(
    fontFamily: dataFont.family,
    fontFamilyFallback: dataFont.fallback,
    fontSize: size,
    color: color ?? tx3,
    fontWeight: weight,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  TextStyle bodyStyle({
    double size = 12.5,
    Color? color,
    double height = 1.5,
  }) => TextStyle(
    fontFamily: bodyFont.family,
    fontFamilyFallback: bodyFont.fallback,
    fontSize: size,
    color: color ?? tx2,
    height: height,
  );
}

/// Provides the active theme to a layout subtree.
///
/// Only the alternate layouts are wrapped — Classic is deliberately outside,
/// because it keeps its own private widgets and its own look.
///
/// An [InheritedTheme], not a plain InheritedWidget: `InheritedTheme.capture`
/// silently SKIPS plain inherited widgets, so dialogs and sheets launched from
/// a themed layout used to lose the scope unless every launcher re-wrapped it
/// by hand. As an InheritedTheme it rides the same capture that already
/// carries `Theme` into `showDialog`/`showModalBottomSheet` builders.
class DetailThemeScope extends InheritedTheme {
  final DetailTheme theme;

  const DetailThemeScope({
    super.key,
    required this.theme,
    required super.child,
  });

  @override
  Widget wrap(BuildContext context, Widget child) =>
      DetailThemeScope(theme: theme, child: child);

  /// Themes are const singletons, so identity is the right comparison and
  /// there is no fifty-field `==` to keep correct.
  @override
  bool updateShouldNotify(DetailThemeScope oldWidget) =>
      !identical(oldWidget.theme, theme);

  /// For widgets that are always inside a themed layout.
  ///
  /// Asserts when the scope is missing: a silent fallback would make a
  /// migration mistake look correct, but only under the default theme.
  static DetailTheme of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DetailThemeScope>();
    assert(
      scope != null,
      'DetailThemeScope.of() called outside a themed layout. Modal sheets do '
      'not inherit it — pass the theme explicitly, or use maybeOf if the '
      'widget is genuinely shared with Classic.',
    );
    return scope?.theme ?? DetailThemes.signal;
  }

  /// For widgets shared with Classic, which renders them unthemed.
  static DetailTheme maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DetailThemeScope>()?.theme ??
      DetailThemes.signal;
}
