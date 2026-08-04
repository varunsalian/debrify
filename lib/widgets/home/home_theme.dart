import 'package:flutter/material.dart';

/// Design tokens for the cinematic Home screen.
///
/// Apple-TV-inspired: content carries the color, chrome stays out of the way.
/// The accent is reserved for active states (focus glow, "live" badge);
/// progress bars and chrome use neutral white instead of an accent gradient.
class HomeTheme {
  HomeTheme._();

  // ── Color ────────────────────────────────────────────────────────────────
  /// Soft indigo — used for focus glow on hero cards only.
  static const Color accent = Color(0xFF818CF8);

  /// Cinematic focus accent for poster tiles & detail-screen actions — a warm
  /// gold that reads as premium "film", distinct from the indigo chrome
  /// accent. Pair [focusGold] (crisp rim) with [focusGoldDeep] (soft bloom).
  static const Color focusGold = Color(0xFFFBBF24);
  static const Color focusGoldDeep = Color(0xFFF59E0B);

  /// Warm highlight — reserved for "live" / now-playing indicators only.
  static const Color highlight = Color(0xFFF59E0B);

  /// Destructive-action color.
  static const Color danger = Color(0xFFEF4444);

  /// Deep card background used by hero cards.
  static const Color cardBg = Color(0xFF0B0B10);

  /// Base page background (the darkest stop of [pageBackground]).
  static const Color bg = Color(0xFF0D0B1A);

  /// Chrome accent — the purple used for active/selected controls (search pill,
  /// mode toggle). Distinct from [focusGold] (content focus) and [accent]
  /// (indigo hero glow).
  static const Color chromeAccent = Color(0xFF7B5CFF);

  /// The cinematic page wash used by the Home board — a dim indigo bloom near
  /// the top fading to near-black. Shared so other screens (Stremio TV, …) sit
  /// on the same background instead of a flat black.
  static const BoxDecoration pageBackground = BoxDecoration(
    gradient: RadialGradient(
      center: Alignment(0, -0.75),
      radius: 1.35,
      colors: [
        Color(0xFF241E44), // dim indigo bloom
        Color(0xFF161327),
        Color(0xFF0F0D1D),
        Color(0xFF0D0B1A),
      ],
      stops: [0.0, 0.38, 0.68, 1.0],
    ),
  );

  // ── Gradients ────────────────────────────────────────────────────────────
  /// "Live" / now-playing pulse gradient.
  static const LinearGradient livePulseGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
  );

  /// Cinematic progress-bar fill — pure white, slightly off at the tail.
  static const LinearGradient progressGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFFFFFFF), Color(0xCCFFFFFF)],
  );

  /// Track behind a progress fill.
  static const Color progressTrack = Color(0x24FFFFFF);

  // ── Image decode caps ─────────────────────────────────────────────────────
  /// memCacheWidth for a full-bleed hero/stage backdrop. One cap shared by
  /// every cinematic backdrop (Home/Search hero, Stremio TV stage) so tuning
  /// it for weak TV hardware happens in exactly one place.
  static const int heroBackdropCacheWidthTv = 1080;
  static const int heroBackdropCacheWidth = 1280;

  /// CachedNetworkImage fade durations for TV-visible surfaces: package
  /// defaults off-TV, a SHORT fade on TV — posters snapping in as hard
  /// rectangles was the last "cheap" tell at the card level. 150ms keeps the
  /// overlap window tiny when a board fills (memory-cached images skip the
  /// fade entirely — OctoImage lands synchronous loads settled — so the
  /// many-saveLayers-at-once case is only ever fresh disk/network arrivals,
  /// which IO already staggers). One helper so every site stays in lockstep —
  /// including catalog_item_tile's board-chrome path, which opts into this
  /// fade; its classic path keeps its own intentionally snappier one.
  static Duration imageFadeIn(bool isTelevision) =>
      isTelevision ? const Duration(milliseconds: 150) : const Duration(milliseconds: 500);
  static Duration imageFadeOut(bool isTelevision) =>
      isTelevision ? const Duration(milliseconds: 150) : const Duration(milliseconds: 1000);

  // ── Responsive ────────────────────────────────────────────────────────────
  /// Returns sizing tokens scaled to the current screen width.
  static HomeMetrics metricsOf(
    BuildContext context, {
    bool isTelevision = false,
  }) {
    final w = MediaQuery.of(context).size.width;
    if (isTelevision || w >= 1280) return HomeMetrics.tv;
    if (w >= 900) return HomeMetrics.tablet;
    if (w >= 600) return HomeMetrics.large;
    return HomeMetrics.compact;
  }
}

/// Per-breakpoint sizing tokens for home section headers.
class HomeMetrics {
  final double sectionHPadding;
  final double sectionVPadding;
  final double headerFontSize;

  const HomeMetrics({
    required this.sectionHPadding,
    required this.sectionVPadding,
    required this.headerFontSize,
  });

  static const compact = HomeMetrics(
    sectionHPadding: 16,
    sectionVPadding: 6,
    headerFontSize: 17,
  );

  static const large = HomeMetrics(
    sectionHPadding: 20,
    sectionVPadding: 8,
    headerFontSize: 18,
  );

  static const tablet = HomeMetrics(
    sectionHPadding: 28,
    sectionVPadding: 10,
    headerFontSize: 20,
  );

  static const tv = HomeMetrics(
    sectionHPadding: 40,
    sectionVPadding: 12,
    headerFontSize: 24,
  );
}

/// Cinematic section header used by all Home sections.
///
/// Apple-TV-inspired: oversized bold title, no chrome. An inline muted count
/// sits to the right of the title for tally without distracting from content.
class HomeSectionHeader extends StatelessWidget {
  final String title;
  final int? count;
  final Widget? trailing;
  final bool isTelevision;
  final EdgeInsetsGeometry? padding;

  const HomeSectionHeader({
    super.key,
    required this.title,
    this.count,
    this.trailing,
    this.isTelevision = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final m = HomeTheme.metricsOf(context, isTelevision: isTelevision);
    final fontSize = m.headerFontSize + 4;

    return Padding(
      padding: padding ??
          EdgeInsets.fromLTRB(
            m.sectionHPadding,
            m.sectionVPadding + 18,
            m.sectionHPadding,
            m.sectionVPadding + 6,
          ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 10),
            Text(
              '$count',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.32),
                fontSize: fontSize - 6,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
