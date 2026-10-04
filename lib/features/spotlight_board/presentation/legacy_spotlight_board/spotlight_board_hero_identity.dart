import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_logo_or_title.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_metrics.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/material.dart';

class SpotlightBoardHeroIdentity {
  final SpotlightBoardDependencies _deps;
  SpotlightBoardHeroIdentity(this._deps);
  SpotlightBoardWidgetView get view => _deps.view;
  SpotlightBoardSections get _sections => _deps.sections;
  Widget identity(StremioMeta item, bool flip, SpotlightBoardMetrics m) {
    final cross = flip ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final align = flip ? TextAlign.right : TextAlign.left;
    return Column(
      crossAxisAlignment: cross,
      mainAxisSize: MainAxisSize.min,
      children: [
        SpotlightBoardLogoOrTitle(
          url: item.logo,
          name: item.name,
          align: align,
          scale: m.k,
        ),
        const SizedBox(height: 9),
        Text(
          [
            item.type == 'series' ? 'Series' : 'Film',
            ...(item.genres ?? const []).take(2),
          ].join(' · '),
          textAlign: align,
          style: TextStyle(
            fontSize: 10.5 * m.k,
            color: Colors.white.withValues(alpha: 0.86),
          ),
        ),
        if ((item.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            item.description!,
            maxLines: 2,
            textAlign: align,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5 * m.k,
              height: 1.42,
              color: Colors.white.withValues(alpha: 0.74),
            ),
          ),
        ],
      ],
    );
  }

  Widget dots({bool tappable = false}) => Row(
    // Keyed so the single-page guard is pinnable: the board grew other
    // AnimatedContainers (the off-parallax focus ring), so "no
    // AnimatedContainer anywhere" stopped meaning "no dots".
    key: const ValueKey('spotlight-hero-dots'),
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < view.hero.length; i++)
        GestureDetector(
          // A 4px dot is not a tap target — the padding is.
          onTap: tappable ? () => _sections.cadence.jumpTo(i) : null,
          behavior: tappable ? HitTestBehavior.opaque : null,
          child: Padding(
            padding: tappable
                ? const EdgeInsets.symmetric(horizontal: 2, vertical: 8)
                : EdgeInsets.zero,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 2.25),
              width: i == _sections.heroArt.heroIndex ? 11 : 4,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: i == _sections.heroArt.heroIndex ? 0.95 : 0.34,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
    ],
  );
}
