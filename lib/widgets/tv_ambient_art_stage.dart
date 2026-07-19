import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/main_page_bridge.dart';

const Color _bg = Color(0xFF0D0B1A); // kStremioBg — the app's page ink

/// The TV shell's GLASS STAGE: the Home board's focused title art, blurred,
/// filling the WHOLE screen — behind the tab content AND the sidebar rail
/// (the Home board's scaffold goes transparent over it). The "blur" is the
/// tiny-decode trick (decode at 96px, cover-stretch — bilinear upscale does
/// the softening): no BackdropFilter, no saveLayer, banned on TV anyway.
/// With a blurry background everywhere, every translucent panel above
/// (sidebar glass, chips, veils) reads as frosted glass for free.
///
/// Driven by [MainPageBridge.tvAmbientArt] + [MainPageBridge.tvHeroTint],
/// which the Home board publishes only on its 260ms focus-settle cadence —
/// this widget never rebuilds per keypress. Title changes crossfade 220ms
/// between two cached textures (no re-raster); tint settles rebuild the
/// washes in place (snap — the TV policy). Null art = the flat page ink,
/// which is also what every non-Home tab sits on (their scaffolds are
/// opaque and simply cover this).
class TvAmbientArtStage extends StatelessWidget {
  const TvAmbientArtStage({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: ValueListenableBuilder<String?>(
          valueListenable: MainPageBridge.tvAmbientArt,
          builder: (context, art, _) => ValueListenableBuilder<Color?>(
            valueListenable: MainPageBridge.tvHeroTint,
            builder: (context, tint, __) {
              final t = tint ?? _bg;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Stack(
                  // Keyed by URL: tint-only updates rebuild the washes in
                  // place; only a NEW art crossfades.
                  key: ValueKey(art ?? ''),
                  fit: StackFit.expand,
                  children: [
                    // ALWAYS-opaque base — not an else-branch: while a
                    // first-seen URL fetches/decodes, the image slot paints
                    // nothing, and without this the transparent Home scaffold
                    // showed the app-shell gradient (a DIFFERENT navy) before
                    // the art popped in. Fading art→ink→art all in the same
                    // hue reads intentional.
                    const ColoredBox(color: _bg),
                    if (art != null && art.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: art,
                        fit: BoxFit.cover,
                        // Tiny on purpose — the upscale IS the blur.
                        memCacheWidth: 96,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (_, __) =>
                            const ColoredBox(color: _bg),
                        errorWidget: (_, __, ___) =>
                            const ColoredBox(color: _bg),
                      ),
                    // Tint wash: the film's colour laid diagonally over its
                    // own art, calm toward the lower right.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(_bg, t, 0.45)!.withValues(alpha: 0.38),
                            Color.lerp(_bg, t, 0.25)!.withValues(alpha: 0.26),
                            _bg.withValues(alpha: 0.22),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                    // Legibility floor: art breathes up top, rows and labels
                    // sit on deep glass below.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x330D0B1A),
                            Color(0x730D0B1A),
                            Color(0xC90D0B1A),
                          ],
                          stops: [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
