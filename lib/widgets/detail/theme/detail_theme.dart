import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'detail_themes.dart';

/// Which family a role uses. A theme names a ROLE, never a font, so it can
/// never ask for a face the platform doesn't have.
enum DetailFontRole { sans, serif, mono }

extension DetailFontRoleX on DetailFontRole {
  /// Null means "the platform default", which is what every Signal text style
  /// resolves to today — so Signal keeps its exact metrics.
  String? get family => switch (this) {
    DetailFontRole.sans => null,
    DetailFontRole.serif => 'serif',
    DetailFontRole.mono => 'monospace',
  };

  List<String>? get fallback => switch (this) {
    DetailFontRole.sans => null,
    DetailFontRole.serif => const ['Georgia', 'Times New Roman', 'Noto Serif'],
    DetailFontRole.mono => const ['Menlo', 'Courier New', 'Noto Sans Mono'],
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
class DetailThemeScope extends InheritedWidget {
  final DetailTheme theme;

  const DetailThemeScope({
    super.key,
    required this.theme,
    required super.child,
  });

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
