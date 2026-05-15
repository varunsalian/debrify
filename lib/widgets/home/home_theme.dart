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

  /// Warm highlight — reserved for "live" / now-playing indicators only.
  static const Color highlight = Color(0xFFF59E0B);

  /// Destructive-action color.
  static const Color danger = Color(0xFFEF4444);

  /// Deep card background used by hero cards.
  static const Color cardBg = Color(0xFF0B0B10);

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
