/// The touch/desktop transport dock's look and size, chosen in
/// Settings → Appearance and persisted as three independent preferences:
/// `player_dock_style`, `player_dock_palette` and `player_dock_size`.
///
/// Read once at player launch (alongside `iptv_player_guide_style`), so a
/// change applies to the next playback session.
///
/// Deliberately NOT wired to the app theme. The player is a theme-EXCLUDED
/// surface — `pushExcluded` / `FrozenLegacyPageRoute` / `LegacyThemeBoundary`,
/// with `kStillFrozenPaths` in `test/theme/source_guard_test.dart` covering
/// `lib/screens/video_player/` — so nothing here may read `AppThemeScope`.
/// The dock also lives over video whose colour grade changes every second,
/// which is a different problem from skinning a settings page.
///
/// See `dev/design/plans/PLAYER_DOCK_STYLES_PLAN.md` for the full contract; the section
/// numbers cited below refer to it.
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

/// Which dock layout to build.
///
/// `classic` is the verbatim legacy path: `Controls` branches on style FIRST
/// and only styled branches read [DockMetrics] or [DockPalette], which is what
/// keeps today's dock provably pixel-identical. `NetflixControlButton` is used
/// only by that branch and is not modified.
enum PlayerDockStyle {
  classic,

  /// The styled dock, picking its arrangement from the viewport. What
  /// `two_tier` always meant; kept as the sensible default.
  auto,

  /// Force one row plus an overflow sheet, whatever the window size.
  compact,

  /// Force the two-tier stack: centred transport over the scrubber, tools
  /// wrapping below.
  tiers,

  /// Force the zoned bar: transport + volume + time / title / icon-only
  /// tools. Needs real width; falls back when it cannot fit.
  cinema;

  static PlayerDockStyle fromPref(String? raw) => switch (raw) {
    // `two_tier` is the value shipped before the arrangements became
    // selectable, and it meant exactly what `auto` means now.
    'auto' || 'two_tier' => PlayerDockStyle.auto,
    'compact' => PlayerDockStyle.compact,
    'tiers' => PlayerDockStyle.tiers,
    'cinema' => PlayerDockStyle.cinema,
    _ => PlayerDockStyle.classic,
  };

  String get prefValue => switch (this) {
    PlayerDockStyle.classic => 'classic',
    PlayerDockStyle.auto => 'auto',
    PlayerDockStyle.compact => 'compact',
    PlayerDockStyle.tiers => 'tiers',
    PlayerDockStyle.cinema => 'cinema',
  };

  bool get isStyled => this != PlayerDockStyle.classic;

  /// The arrangement this style demands, or null when it defers to the
  /// viewport.
  DockArrangement? get forcedArrangement => switch (this) {
    PlayerDockStyle.classic || PlayerDockStyle.auto => null,
    PlayerDockStyle.compact => DockArrangement.narrow,
    PlayerDockStyle.tiers => DockArrangement.regular,
    PlayerDockStyle.cinema => DockArrangement.wide,
  };
}

/// The dock accent. Inert under [PlayerDockStyle.classic] — the setting is
/// preserved so switching back to a styled dock restores the user's choice.
enum PlayerDockPalette {
  ultraviolet,
  crimson,
  aurum,
  ice;

  static PlayerDockPalette fromPref(String? raw) => switch (raw) {
    'crimson' => PlayerDockPalette.crimson,
    'aurum' => PlayerDockPalette.aurum,
    'ice' => PlayerDockPalette.ice,
    _ => PlayerDockPalette.ultraviolet,
  };

  String get prefValue => name;
}

/// Control size. `auto` follows the viewport; the rest **request** a fixed
/// scale that §3.4's vertical budget may reduce but never raise — they are
/// upper bounds, not absolutes.
///
/// What separates them from `auto` is that they do not grow with viewport
/// width: `medium` on a 4K desktop stays at 1.25 where `auto` reaches 1.55.
enum PlayerDockSize {
  auto,
  small,
  medium,
  large;

  static PlayerDockSize fromPref(String? raw) => switch (raw) {
    'small' => PlayerDockSize.small,
    'medium' => PlayerDockSize.medium,
    'large' => PlayerDockSize.large,
    _ => PlayerDockSize.auto,
  };

  String get prefValue => name;

  /// Null for [auto], which derives its scale from the viewport instead.
  double? get requestedK => switch (this) {
    PlayerDockSize.auto => null,
    PlayerDockSize.small => 1.00,
    PlayerDockSize.medium => 1.25,
    PlayerDockSize.large => 1.50,
  };
}

/// Which of the styled dock's three arrangements to build. Chosen from width
/// AND height, never persisted — rotating or resizing re-picks.
///
/// The height gate matters: two tiers cost two target-heights, and a 360lp-tall
/// viewport cannot afford that at any density. [narrow] is a single row.
enum DockArrangement {
  narrow,
  regular,
  wide;

  static DockArrangement forViewport(Size viewport) {
    if (viewport.width < 600 || viewport.height < 480) {
      return DockArrangement.narrow;
    }
    return viewport.width >= 1080
        ? DockArrangement.wide
        : DockArrangement.regular;
  }

  /// Rows of controls the budget must reserve.
  ///
  /// [narrow] is one row. [regular] and [wide] are two — transport tier plus
  /// a tools tier — but the tools tier is a `Wrap` that can run to more than
  /// one line on a narrow-but-tall viewport, so a third row is reserved for
  /// them. Over-reserving costs a little density; under-reserving overflows.
  int get budgetRows => this == DockArrangement.narrow ? 1 : 3;

  /// The transport row is taller than a plain 44lp target: the primary button
  /// is 1.32x. Charged once, to whichever arrangement has a transport row —
  /// all of them do.
  double get primaryOverhang => DockLayoutInput.minTarget * 0.32;

  /// Minimum row WIDTH at k = 1, so the budget can reject a scale the row
  /// cannot physically fit. Vertical fit alone is not enough: an earlier build
  /// approved `large` on a 320lp-wide viewport and overflowed by 14px, because
  /// nothing checked that transport + More still fit side by side.
  ///
  /// [narrow] is one row — prev(1) + primary(1.32) + next(1) + More(1) target
  /// widths, four gaps, plus the dock's horizontal padding.
  /// [regular] wraps its tools onto further lines; [wide] scrolls its
  /// icon-only cluster. Either way only the transport is modelled here.
  double get minRowWidthAtK1 {
    const t = DockLayoutInput.minTarget;
    const padding = 2 * 10 * 1.8;
    // The label allowance is what the earlier estimate missed: `More` and the
    // promoted chips carry text, and a target-width estimate ignored it. The
    // numbers are validated by dock_layout_test, which renders the densest
    // possible row at every viewport and text scale.
    const labelAllowance = 76.0;
    return this == DockArrangement.narrow
        ? (t * 4.32) + (8 * 4) + padding + labelAllowance
        : (t * 3.32) + (8 * 2) + padding + 24;
  }

  /// Dock vertical padding plus inter-row gaps, at the worst-case k of 1.55:
  /// `2 × 8 × 1.55 = 24.8` padding, plus `8 × 1.55 = 12.4` per gap.
  double get gapsAtMaxK => this == DockArrangement.narrow ? 38 : 50;
}

/// The dock's colour tokens — fourteen, because a smaller set cannot paint the
/// dock without hardcoded literals, which would defeat the palette entirely.
///
/// Every alpha is pre-multiplied into the colour. House rule: no `Opacity`
/// widgets over video.
@immutable
class DockPalette {
  /// Accent gradient. The primary runs `hot → deep`; the scrub fill runs
  /// `deep → hot`, so the played edge is the brightest point on the bar.
  final Color hot;
  final Color deep;

  /// 1px highlight along the primary's top edge. Part of what makes the
  /// button read as a lit object rather than a filled circle.
  final Color specular;

  /// Glow cast onto the scrim beneath the primary, in two layers.
  final Color glow;

  /// Chapter / skip-segment ticks, and armed-state text (sleep timer).
  final Color tick;

  final Color activeFill;
  final Color activeEdge;

  /// Ink ON the primary button. [aurum] is the only palette where this is
  /// dark — a real branch, not a token swap. Hardcoding white here ships an
  /// invisible play glyph.
  final Color onPrimary;

  final Color chipFill;
  final Color chipEdge;

  final Color ink;
  final Color inkDim;

  /// Unplayed portion of the scrub track.
  final Color inactiveTrack;

  /// Live capture. NOT a palette variant — a recording is a state the user
  /// must recognise instantly, so a palette that could recolour it could hide
  /// it. Identical in all four.
  static const Color record = Color(0xFFF43F5E);

  /// The dock's gradient base over video. Near-identical across palettes by
  /// design: the dock stays dark over footage whatever the accent.
  final Color scrim;

  const DockPalette({
    required this.hot,
    required this.deep,
    required this.specular,
    required this.glow,
    required this.tick,
    required this.activeFill,
    required this.activeEdge,
    required this.onPrimary,
    required this.chipFill,
    required this.chipEdge,
    required this.ink,
    required this.inkDim,
    required this.inactiveTrack,
    required this.scrim,
  });
}

abstract final class DockPalettes {
  /// Shared neutrals. The dock is dark over video in every palette, so only
  /// the accent family actually varies.
  static const Color _ink = Color(0xFFFFFFFF);
  static const Color _inkDim = Color(0xA6FFFFFF);
  static const Color _chipFill = Color(0x14FFFFFF);
  static const Color _chipEdge = Color(0x1FFFFFFF);
  static const Color _inactiveTrack = Color(0x38FFFFFF);
  static const Color _scrim = Color(0xF0040610);

  /// Hot magenta falling into deep violet. The default, and the only palette
  /// that still reads as Debrify rather than as somebody else.
  static const DockPalette ultraviolet = DockPalette(
    hot: Color(0xFFFF3DA6),
    deep: Color(0xFF6D2BFF),
    specular: Color(0x6BFFFFFF),
    glow: Color(0x9E9E3CFF),
    tick: Color(0xFFFFC2E4),
    activeFill: Color(0x38A046FF),
    activeEdge: Color(0x85A046FF),
    onPrimary: _ink,
    chipFill: _chipFill,
    chipEdge: _chipEdge,
    ink: _ink,
    inkDim: _inkDim,
    inactiveTrack: _inactiveTrack,
    scrim: _scrim,
  );

  /// Cinema red done properly — hot scarlet dropping to oxblood, versus the
  /// flat single-value `0xFFE50914` the legacy dock uses in four places.
  static const DockPalette crimson = DockPalette(
    hot: Color(0xFFFF3A52),
    deep: Color(0xFFB00418),
    specular: Color(0x66FFFFFF),
    glow: Color(0x9EFF2D41),
    tick: Color(0xFFFFC9CF),
    activeFill: Color(0x38FF3A52),
    activeEdge: Color(0x8CFF3A52),
    onPrimary: _ink,
    chipFill: _chipFill,
    chipEdge: _chipEdge,
    ink: _ink,
    inkDim: _inkDim,
    inactiveTrack: _inactiveTrack,
    scrim: _scrim,
  );

  /// Metallic gold — champagne into old brass. The prestige register, and the
  /// ONLY palette with dark ink on the primary.
  static const DockPalette aurum = DockPalette(
    hot: Color(0xFFFFE7A3),
    deep: Color(0xFFC1861A),
    specular: Color(0x99FFFFFF),
    glow: Color(0x8CD79B28),
    tick: Color(0xFFFFE7A3),
    activeFill: Color(0x33E6B446),
    activeEdge: Color(0x8CE6B446),
    onPrimary: Color(0xFF2A1B00),
    chipFill: _chipFill,
    chipEdge: _chipEdge,
    ink: _ink,
    inkDim: _inkDim,
    inactiveTrack: _inactiveTrack,
    scrim: _scrim,
  );

  /// Electric cyan into deep blue — coldest and highest-contrast over dark
  /// footage.
  static const DockPalette ice = DockPalette(
    hot: Color(0xFF7BF1FF),
    deep: Color(0xFF0A5CFF),
    specular: Color(0x8CFFFFFF),
    glow: Color(0x9E288CFF),
    tick: Color(0xFFC6F3FF),
    activeFill: Color(0x3846BEFF),
    activeEdge: Color(0x8C46BEFF),
    onPrimary: Color(0xFF00203D),
    chipFill: _chipFill,
    chipEdge: _chipEdge,
    ink: _ink,
    inkDim: _inkDim,
    inactiveTrack: _inactiveTrack,
    scrim: _scrim,
  );

  static DockPalette of(PlayerDockPalette palette) => switch (palette) {
    PlayerDockPalette.ultraviolet => ultraviolet,
    PlayerDockPalette.crimson => crimson,
    PlayerDockPalette.aurum => aurum,
    PlayerDockPalette.ice => ice,
  };
}

/// Everything [DockMetrics.compute] needs to resolve a scale. Passed as one
/// object so the vertical budget can account for the whole column, not just
/// the dock: the top bar shares the same `spaceBetween` column.
@immutable
class DockLayoutInput {
  final Size viewport;
  final EdgeInsets safeArea;
  final DockArrangement arrangement;

  /// Measured panel height, or [kInfoPanelBound] on the first pass. See §5.3 —
  /// the host owns this, because it builds the panel and therefore knows when
  /// its structure changes without introspecting an opaque widget.
  final double infoPanelH;

  /// Clamped ambient text scaler. Feeds the label-fit checks in the collapse
  /// ladder and the panel-geometry signature — it does NOT feed the scrubber
  /// bound, which is fixed.
  final double textScale;

  final PlayerDockSize size;

  const DockLayoutInput({
    required this.viewport,
    required this.safeArea,
    required this.arrangement,
    required this.infoPanelH,
    required this.textScale,
    required this.size,
  });

  /// Conservative bound on the top bar: the current top row is the MAX of its
  /// 48lp `IconButton` and the title/subtitle column, never their sum, so 72
  /// only ever over-reserves.
  static const double topBarH = 72;

  /// Fixed bound on the styled seek row — never scaled. An unconstrained
  /// Material `Slider` claims ~48lp on its own, so the styled row must be
  /// explicitly constrained; `dock_layout_test` asserts the rendered row
  /// measures at or under this at text scale 1.0 and 1.3.
  static const double scrubberH = 56;

  /// First-pass panel height, before measurement. Verified rather than
  /// guessed: `dock_info_panel_bound_test` measures the real maximum across
  /// every guide style, both text scales and the layout-boundary widths, and
  /// asserts it stays under this.
  static const double kInfoPanelBound = 200;

  /// The smallest touch target the dock may ever produce. A floor, not a base:
  /// no size override may breach it, which is the whole point of the feature.
  static const double minTarget = 44;

  static const double maxK = 1.55;
}

/// Resolved dock geometry. Every value is already multiplied by `k`.
@immutable
class DockMetrics {
  final double k;
  final double icon;
  final double label;
  final double target;
  final double padX;
  final double padY;
  final double gap;
  final double radius;
  final double trackHeight;
  final double knob;

  const DockMetrics._({
    required this.k,
    required this.icon,
    required this.label,
    required this.target,
    required this.padX,
    required this.padY,
    required this.gap,
    required this.radius,
    required this.trackHeight,
    required this.knob,
  });

  /// Resolve metrics for [input], or **null** when the viewport cannot seat a
  /// single 44lp row — the caller then renders `classic`.
  ///
  /// There is no fixed minimum viewport: the boundary depends on insets, panel
  /// content and text scale, so it is computed rather than declared.
  ///
  /// Pure — unit-testable with no widget tree.
  static DockMetrics? compute(DockLayoutInput input) {
    final requested = input.size.requestedK ?? _autoK(input.viewport);

    // Everything else in the column, so the dock cannot claim room the top bar
    // and info panel need. `gaps` is evaluated at the worst-case k because it
    // scales with density; using the live k would make this circular.
    // `scrubberH` is fixed and needs no worst-case evaluation.
    final reserved =
        input.safeArea.top +
        input.safeArea.bottom +
        DockLayoutInput.topBarH +
        input.infoPanelH +
        DockLayoutInput.scrubberH +
        input.arrangement.gapsAtMaxK +
        // The primary transport button is 1.32x a plain target; the row is
        // that tall, not 44.
        input.arrangement.primaryOverhang;

    final budget = input.viewport.height - reserved;
    final fitK =
        budget / (input.arrangement.budgetRows * DockLayoutInput.minTarget);

    // Unclamped on purpose: fitK < 1 is a real outcome and means one 44lp row
    // does not fit. Clamping first would make the test unreachable.
    if (fitK < 1.0) return null;

    // Horizontal fit, judged on its own budget. A row that cannot fit its
    // transport plus More is not a smaller row — it is an overflow.
    // The dock sits inside a horizontal SafeArea, so a landscape cutout or
    // rounded corner really does take this width away.
    final usableWidth =
        input.viewport.width - input.safeArea.left - input.safeArea.right;
    final fitKWidth = usableWidth / input.arrangement.minRowWidthAtK1;
    if (fitKWidth < 1.0) return null;

    final k = math.min(
      math.min(math.min(requested, fitK), fitKWidth),
      DockLayoutInput.maxK,
    );
    return _forScale(k);
  }

  /// Convenience wrapper over [compute] for widget code. [infoPanelH] is
  /// supplied by the host, which owns the measurement (§5.3).
  static DockMetrics? of(
    BuildContext context,
    PlayerDockSize size, {
    required double infoPanelH,
  }) {
    final media = MediaQuery.of(context);
    return compute(
      DockLayoutInput(
        viewport: media.size,
        safeArea: media.padding,
        arrangement: DockArrangement.forViewport(media.size),
        infoPanelH: infoPanelH,
        textScale: media.textScaler.scale(1),
        size: size,
      ),
    );
  }

  /// Viewport-derived scale for [PlayerDockSize.auto]. Width and height are
  /// judged on their own budgets and the smaller wins — a 1600×500 window and
  /// a 900×900 window have very different horizontal room, and a single
  /// shortest-side reading cannot tell them apart.
  static double _autoK(Size viewport) {
    final widthK = lerpDouble(
      1.0,
      1.55,
      ((viewport.width - 600) / 1600).clamp(0.0, 1.0),
    )!;
    final heightK = lerpDouble(
      1.0,
      1.35,
      ((viewport.height - 360) / 840).clamp(0.0, 1.0),
    )!;
    return math.min(widthK, heightK);
  }

  static DockMetrics _forScale(double k) => DockMetrics._(
    k: k,
    icon: 20 * k,
    // The BASE size only. Labels ride the platform's own clamped textScaler
    // (main.dart caps it at 1.3), and Android's curve is non-linear — feeding
    // a pre-multiplied value here would scale twice and blow out the row.
    label: 12 * k,
    target: math.max(DockLayoutInput.minTarget, DockLayoutInput.minTarget * k),
    padX: 10 * k,
    padY: 8 * k,
    gap: 8 * k,
    radius: 10 * k,
    trackHeight: 4 * k,
    knob: 12 * k,
  );
}
