import 'package:flutter/material.dart';

/// The IPTV cockpit's visual style, chosen in IPTV settings and persisted as
/// the `iptv_style` preference (see `StorageService.getIptvStyle`).
///
/// `command` is the shipped Command Center look and takes the UNTOUCHED legacy
/// build paths everywhere — widgets branch on the style FIRST and only the
/// `edition`/`console` branches read [IptvStyleTokens], which is what makes
/// the default provably pixel-identical to today.
///
/// Only the TV/desktop cockpit consults this. The phone classic layout and
/// the touch-tablet two-pane never restyle.
enum IptvStyle {
  command,
  edition,
  console;

  static IptvStyle fromPref(String raw) => switch (raw) {
    'edition' => IptvStyle.edition,
    'console' => IptvStyle.console,
    _ => IptvStyle.command,
  };

  String get prefValue => name;

  /// Convenience for the common "is this a styled (non-legacy) cockpit" test.
  bool get isStyled => this != IptvStyle.command;
}

/// Design tokens for the two styled looks. `command` deliberately has NO
/// tokens — its widgets never reach for this class.
///
/// Every color that varies by emphasis is expressed as the base color plus
/// the alpha steps the mocks use, so call sites read like the mock CSS
/// (`fg`, `fg70`, `fg45`, `fg28`) instead of scattering `withValues` math.
class IptvStyleTokens {
  final Color bg;

  /// Panel/surface tone where the legacy look used its navy panel.
  final Color panel;

  /// Foreground ramp — 100 / ~80|70 / ~55|45 / ~35|28 per the mocks.
  final Color fg;
  final Color fgMid;
  final Color fgDim;
  final Color fgFaint;

  /// Hairline rules — the only borders these styles draw.
  final Color hairline;
  final Color hairline2;

  /// Semantic accents. [accent] is the style's single non-semantic color
  /// (edition: paper — i.e. none; console: amber) and must stay reserved for
  /// focus/time machinery per the design rules.
  final Color accent;
  final Color rec;
  final Color live;

  /// Selected-row tint (rail) and focused-row tint (grid).
  final Color selectedTint;
  final Color focusTint;

  /// Display families. Empty string = use the app default family.
  final String headlineFamily; // edition: Fraunces72
  final String captionFamily; // edition: Fraunces9 (italic captions)
  final String nameFamily; // console: SpaceGrotesk
  final String monoFamily; // console: JetBrainsMono

  const IptvStyleTokens({
    required this.bg,
    required this.panel,
    required this.fg,
    required this.fgMid,
    required this.fgDim,
    required this.fgFaint,
    required this.hairline,
    required this.hairline2,
    required this.accent,
    required this.rec,
    required this.live,
    required this.selectedTint,
    required this.focusTint,
    this.headlineFamily = '',
    this.captionFamily = '',
    this.nameFamily = '',
    this.monoFamily = '',
  });

  /// First Edition — warm ink + paper, serif headline, hairline ledger.
  static const IptvStyleTokens edition = IptvStyleTokens(
    bg: Color(0xFF0D0B09),
    panel: Color(0xFF141110),
    fg: Color(0xFFF3EEE3),
    fgMid: Color(0xCCF3EEE3), // 80%
    fgDim: Color(0x8CF3EEE3), // 55%
    fgFaint: Color(0x59F3EEE3), // 35%
    hairline: Color(0x17F3EEE3), // 9%
    hairline2: Color(0x29F3EEE3), // 16%
    accent: Color(0xFFF3EEE3), // paper — edition has no color accent
    rec: Color(0xFFE5484D),
    live: Color(0xFFB8C79B),
    selectedTint: Color(0x0DF3EEE3), // 5%
    focusTint: Color(0x09F3EEE3), // 3.5%
    headlineFamily: 'Fraunces72',
    captionFamily: 'Fraunces9',
  );

  /// Master Control — pure black instrument, amber time machinery.
  static const IptvStyleTokens console = IptvStyleTokens(
    bg: Color(0xFF050505),
    panel: Color(0xFF0A0A0A),
    fg: Color(0xFFEDEDED),
    fgMid: Color(0xB3EDEDED), // 70%
    fgDim: Color(0x73EDEDED), // 45%
    fgFaint: Color(0x47EDEDED), // 28%
    hairline: Color(0x14FFFFFF), // 8%
    hairline2: Color(0x26FFFFFF), // 15%
    accent: Color(0xFFF2A93B), // amber — time/focus/playhead ONLY
    rec: Color(0xFFFF4545),
    live: Color(0xFF34D399), // matches the app's emerald live dot
    selectedTint: Color(0x0FF2A93B), // 6% amber
    focusTint: Color(0x0DF2A93B), // 5% amber
    nameFamily: 'SpaceGrotesk',
    monoFamily: 'JetBrainsMono',
  );

  static IptvStyleTokens? of(IptvStyle style) => switch (style) {
    IptvStyle.command => null,
    IptvStyle.edition => edition,
    IptvStyle.console => console,
  };
}

/// Master Control's focus cue: four corner brackets, painted as a
/// foregroundPainter on the FOCUSED row only — the unfocused 50k rows pay
/// nothing for it.
class IptvFocusBracketsPainter extends CustomPainter {
  final Color color;
  const IptvFocusBracketsPainter(this.color);

  static const double _arm = 9;
  static const double _inset = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final l = _inset;
    final r = size.width - _inset;
    final t = _inset;
    final b = size.height - _inset;
    final path = Path()
      // top-left
      ..moveTo(l, t + _arm)
      ..lineTo(l, t)
      ..lineTo(l + _arm, t)
      // top-right
      ..moveTo(r - _arm, t)
      ..lineTo(r, t)
      ..lineTo(r, t + _arm)
      // bottom-right
      ..moveTo(r, b - _arm)
      ..lineTo(r, b)
      ..lineTo(r - _arm, b)
      // bottom-left
      ..moveTo(l + _arm, b)
      ..lineTo(l, b)
      ..lineTo(l, b - _arm);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(IptvFocusBracketsPainter oldDelegate) =>
      oldDelegate.color != color;
}
