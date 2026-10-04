import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

class SpotlightBoardHeroBackdrop {
  final SpotlightBoardDependencies _deps;
  SpotlightBoardHeroBackdrop(this._deps);
  SpotlightBoardWidgetView get view => _deps.view;
  SpotlightBoardOwners get _owners => _deps.owners;
  SpotlightBoardSections get _sections => _deps.sections;
  Widget heroBackdropContent(double heroH) {
    final item = _sections.heroArt.heroItem;
    if (item == null) return const SizedBox.shrink();
    final url = _sections.heroArt.heroArt(item);
    final posterUrl = _sections.heroArt.heroPoster(item);
    final flip = _sections.ambient.flip;
    // Both scrims below were tuned against a STILL, where they only have to
    // keep white text off busy artwork. Left at that strength over a moving
    // picture they are most of why the trailer reads dim: the identity scrim
    // blacks out the left two thirds, and the ground fade covers 260 of the
    // band's 540 across its full width.
    //
    // The page already has a name for this — theater, "veils thin to
    // near-clear" — but that flag is read only inside the Canvas branch and
    // never reaches this board, so Spotlight armed the timer and got none of
    // the lift. Driven off the board's own cadence flag instead, which is the
    // thing that actually knows a picture is rolling.
    //
    // Snapped, not tweened: animating a full-width gradient every frame is
    // exactly what the TV veil policy exists to avoid.
    final rolling = _owners.hero.rolling;
    final app = AppThemeScope.of(_deps.context());
    final ground = view.groundOf(app);
    // The legibility bed under the hero's white identity — always dark, see the
    // gradient below.
    final bed = Color.lerp(ground, const Color(0xFF000000), 0.75)!;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (url != null && url.isNotEmpty)
          CachedNetworkImage(
            imageUrl: url,
            key: ValueKey(url),
            fit: BoxFit.cover,
            cacheManager: DebrifyImageCache.manager,
            // Decode at the PANEL's resolution off-TV, same as the compact
            // hero — 1400 flat was under a retina desktop's physical width,
            // so the one full-bleed image on the screen was the soft one.
            // TV keeps the 1400: its panels sit behind the box's own
            // upscaler and the decode budget there is the tighter constraint
            // (see TvHeroArtworkQuality).
            memCacheWidth: _sections.heroArt.heroDecodeWidth,
            fadeInDuration: _sections.heroArt.heroImageFadeIn,
            fadeOutDuration: _sections.heroArt.heroImageFadeOut,
            placeholder: (_, __) => ColoredBox(color: ground),
            // The derived metahub URL is a GUESS — when it 404s (no still
            // for that title), fall back to the poster rather than a flat
            // ground: a soft hero beats a blank one.
            errorWidget: (_, __, ___) =>
                (posterUrl != null && posterUrl.isNotEmpty && posterUrl != url)
                ? CachedNetworkImage(
                    imageUrl: posterUrl,
                    fit: BoxFit.cover,
                    cacheManager: DebrifyImageCache.manager,
                    memCacheWidth: 1400,
                    placeholder: (_, __) => ColoredBox(color: ground),
                    errorWidget: (_, __, ___) => ColoredBox(color: ground),
                  )
                : ColoredBox(color: ground),
          ),
        // Mounted whenever the HOST supplies one — never gated on this
        // board's own `_rolling`.
        //
        // Gating it here kept the layer alive after the host tore the trailer
        // down (`_clearHeroTrailer` on playback launch), so its media_kit
        // engine was still holding a VideoOutput when the player created its
        // own. Two VideoOutputs is SIGABRT on tvOS — the crash was at
        // `enableHardwareAcceleration`, in the second one's constructor.
        //
        // The host already owns this lifecycle for every other board; the
        // board's job is the cadence, and only the cadence.
        if (view.trailer != null) Positioned.fill(child: view.trailer!),
        // The identity scrim, on whichever side the text is. Pinned WITH the
        // art rather than scrolling with the text it serves: it covers that
        // side's full height, so the identity stays on scrimmed picture for
        // its whole upward travel — and a scrim that translated away with
        // the list would drag its visible edge up the artwork.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: flip
                    ? const Alignment(1, -0.2)
                    : const Alignment(-1, -0.2),
                end: flip ? const Alignment(-1, 0.2) : const Alignment(1, 0.2),
                colors: rolling
                    ? const [
                        Color(0x9E000000),
                        Color(0x66000000),
                        Color(0x1C000000),
                        Color(0x00000000),
                      ]
                    : const [
                        Color(0xE0000000),
                        Color(0xA8000000),
                        Color(0x2E000000),
                        Color(0x00000000),
                      ],
                stops: const [0, 0.26, 0.52, 0.68],
              ),
            ),
          ),
        ),
        // Fades into the SHELF GROUND, not into black — a scrim landing on a
        // colour the page never paints leaves a visible seam where the hero
        // ends.
        IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              // Pulled in tight while the picture rolls. The seam still has to
              // be sealed — the bottom stop is the ground colour exactly, so
              // the hero still meets the shelf without a visible edge — but
              // the long soft tail costs half the frame for no legibility.
              //
              // Deliberately absolute, unlike the hero's own height: this is a
              // blend DISTANCE, not a share of the layout, and a fade that
              // scaled with the panel would smear further on a large one for no
              // reason. The identity's `bottom` insets below are the same kind
              // of number.
              height: rolling ? 150 : 260,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    // TWO jobs, and only one of them follows the ground.
                    //
                    // The bottom stop is the page ground exactly, so the hero
                    // meets the shelf with no seam. Everything above it is a
                    // legibility bed for the hero's identity and dots, which
                    // are white because they sit on a photograph — so it stays
                    // DARK. Tinting the whole ramp with the ground put a white
                    // wash under white text the moment a pale background was
                    // chosen.
                    colors: [
                      ground,
                      bed.withValues(alpha: 0.92),
                      bed.withValues(alpha: 0.45),
                      bed.withValues(alpha: 0),
                    ],
                    stops: const [0.04, 0.22, 0.56, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
        // The veil — what going DOWN does to the picture now that it no
        // longer scrolls away. Ground-coloured for the same reason the fade
        // above ends on ground: the rows and their titles are inked for the
        // page ground, so the picture must dim TOWARD it — a black veil
        // would put theme-inked text on a surface the theme never chose.
        //
        // A solid fill whose alpha lives in the COLOUR — an Opacity widget
        // would add a compositing layer per change — inside its own
        // RepaintBoundary, so a veil change redraws one flat quad and never
        // dirties the layer holding the art and both gradients.
        //
        // TWO drivers, per input. TV snaps it off the CURSOR — hero clear,
        // first shelf 0.72, deeper opaque — because tracking the scroll
        // glide repaints every frame of every row move, which is exactly
        // what the TV veil policy exists to avoid (and what a MiBox-class
        // GPU renders as lag). Touch and desktop keep the continuous
        // scroll-driven ramp: free scrolling has no discrete states to snap
        // between, and those GPUs absorb the fill.
        if (!view.animationsEnabled)
          RepaintBoundary(
            child: IgnorePointer(
              child: view.dpad
                  ? SpotlightBoardHeroBackdrop.veil(
                      ground,
                      _owners.navigation.row < 0
                          ? 0.0
                          : (_owners.navigation.row == 0 ? 0.72 : 1.0),
                    )
                  : AnimatedBuilder(
                      animation: Listenable.merge([
                        _owners.scroll.scroll,
                        _owners.scroll.veilMetricsRevision,
                      ]),
                      builder: (context, _) {
                        final off = _owners.scroll.scroll.hasClients
                            ? _owners.scroll.scroll.offset
                            : 0.0;
                        final t = (off / (heroH * 0.8)).clamp(0.0, 1.0);
                        return SpotlightBoardHeroBackdrop.veil(ground, t);
                      },
                    ),
            ),
          ),
      ],
    );
  }

  /// One alpha-in-the-colour fill. Fully transparent paints nothing at all.
  static Widget veil(Color ground, double t) => t <= 0
      ? const SizedBox.shrink()
      : ColoredBox(color: ground.withValues(alpha: t));
}
