import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_logo_or_title.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_metrics.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_hero_open_pill.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

class SpotlightBoardCompactHero {
  final SpotlightBoardDependencies _deps;
  SpotlightBoardCompactHero(this._deps);
  SpotlightBoardWidgetView get view => _deps.view;
  SpotlightBoardOwners get _owners => _deps.owners;
  SpotlightBoardSections get _sections => _deps.sections;
  Widget hero(SpotlightBoardMetrics m, double heroH) {
    if (m.compact) return _sections.compactHero.heroCompact(m);
    return _sections.wideHero.heroWide(m, heroH);
  }

  /// The phone hero — the Apple phone idiom, not the TV hero cropped.
  ///
  /// Centered identity stack over the art's lower third (logo → metadata →
  /// CTA → dots), a vertical scrim whose bottom stop is the page ground
  /// exactly (the seam rule), swipe paging, tappable dots. No description
  /// line and no side-flip heuristic: there is no "side" when the stack is
  /// centered.
  Widget heroCompact(SpotlightBoardMetrics m) {
    final item = _sections.heroArt.heroItem;
    if (item == null) return const SizedBox.shrink();
    final url = _sections.heroArt.heroArt(item);
    final posterUrl = _sections.heroArt.heroPoster(item);
    final app = AppThemeScope.of(_deps.context());
    final ground = view.groundOf(app);
    final rolling = _owners.hero.rolling;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 120) return;
        _sections.cadence.jumpTo(
          (_sections.heroArt.heroIndex + (v < 0 ? 1 : -1) + view.hero.length) %
              view.hero.length,
        );
      },
      onTap: () {
        final addon = view.heroAddon;
        if (addon != null) _sections.heroArt.openHero();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null && url.isNotEmpty)
            CachedNetworkImage(
              imageUrl: url,
              key: ValueKey(url),
              fit: BoxFit.cover,
              cacheManager: DebrifyImageCache.manager,
              // Decode at the PANEL's resolution, not a guessed constant —
              // 900 was under a 1080-class phone's physical width (390 × 3),
              // so the one full-bleed image on the screen was the soft one.
              // Clamped: metahub art tops out around 1920.
              memCacheWidth: _sections.heroArt.heroDecodeWidth,
              fadeInDuration: _sections.heroArt.heroImageFadeIn,
              fadeOutDuration: _sections.heroArt.heroImageFadeOut,
              placeholder: (_, __) => ColoredBox(color: ground),
              // Same guess-404 fallback as the wide backdrop: derived
              // metahub art can miss, and the poster beats a blank hero.
              errorWidget: (_, __, ___) =>
                  (posterUrl != null &&
                      posterUrl.isNotEmpty &&
                      posterUrl != url)
                  ? CachedNetworkImage(
                      imageUrl: posterUrl,
                      fit: BoxFit.cover,
                      cacheManager: DebrifyImageCache.manager,
                      memCacheWidth: 900,
                      placeholder: (_, __) => ColoredBox(color: ground),
                      errorWidget: (_, __, ___) => ColoredBox(color: ground),
                    )
                  : ColoredBox(color: ground),
            ),
          // The trailer, when the host supplies one. This was mounted only in
          // the WIDE hero — so the phone resolved a stream into a layer that
          // was never in the tree, which read as "trailers don't load".
          if (view.trailer != null) Positioned.fill(child: view.trailer!),
          // One vertical scrim doing both jobs: a light cap up top so the
          // status-bar clock stays readable over bright art, and a heavy bed
          // below for the identity — ending ON the ground so the hero meets
          // the rows without a seam. Thinned while the picture rolls, same
          // rule as everywhere else tonight: snapped, and the bottom stop is
          // still the ground exactly so the seam never opens.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: rolling
                      ? [
                          const Color(0x2E000000),
                          const Color(0x00000000),
                          const Color(0x00000000),
                          ground.withValues(alpha: 0.55),
                          ground,
                        ]
                      : [
                          const Color(0x6B000000),
                          const Color(0x00000000),
                          const Color(0x00000000),
                          ground.withValues(alpha: 0.78),
                          ground,
                        ],
                  stops: rolling
                      ? const [0, 0.18, 0.62, 0.88, 1]
                      : const [0, 0.24, 0.46, 0.8, 1],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 12,
            child: _sections.compactHero.identityCompact(item, m),
          ),
        ],
      ),
    );
  }

  Widget identityCompact(StremioMeta item, SpotlightBoardMetrics m) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: SpotlightBoardLogoOrTitle(
            url: item.logo,
            name: item.name,
            align: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          [
            item.type == 'series' ? 'Series' : 'Film',
            ...(item.genres ?? const []).take(2),
          ].join(' · '),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: Colors.white.withValues(alpha: 0.86),
          ),
        ),
        const SizedBox(height: 12),
        // The CTA the mock promises. "Open" rather than "Play": it routes to
        // the detail page (the same thing OK does on TV) — a button that says
        // Play and then shows a detail page would be a lie.
        SpotlightHeroOpenPill(
          onTap: () {
            final addon = view.heroAddon;
            if (addon != null) _sections.heroArt.openHero();
          },
        ),
        if (view.hero.length > 1) ...[
          const SizedBox(height: 13),
          _sections.heroIdentity.dots(tappable: true),
        ],
        const SizedBox(height: 4),
      ],
    );
  }
}
