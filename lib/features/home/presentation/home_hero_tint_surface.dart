import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'home_hero_surface.dart';

/// The hero's colour STAGE (boxed mode): a diagonal wash in the focused
/// title's extracted tint plus a soft glow leaning toward the art region —
/// the left half of the Concept-5 hero. Always on (this IS the rest-state
/// background now that the key art lives in the region on the right, not
/// full-bleed), and the surface the idle art's tinted feathers melt into
/// (mid value ~0.30 meets their 0.34) — no half-poster seam, ever. During
/// playback the lights-off veil above quenches this to near-black so the
/// video's slim neutral feathers match. Baked gradients only — no
/// per-frame layer. Boxed mode only.
Widget buildHomeHeroMoodField({
  required bool boxedTrailer,
  required Color base,
  required Color surface,
  ValueListenable<Color?>? tint,
}) {
  if (!boxedTrailer) return const SizedBox.shrink();
  return IgnorePointer(
    // RepaintBoundary so this layer's repaint never bubbles up and
    // re-rasters the whole hero band (region art included). The colour used
    // to SNAP between settles — a one-frame hue jump across ~60% of the
    // screen. It now TWEENS, but only per settle: the tint changes on its
    // 350ms debounce (never per DPAD step), so this costs ~24 frames of
    // two-gradient repaint inside this boundary per rest — not a per-key
    // cost — and the room's lighting follows the art instead of jumping.
    child: RepaintBoundary(
      child: ValueListenableBuilder<Color?>(
        valueListenable: tint ?? const AlwaysStoppedAnimation<Color?>(null),
        builder: (context, tint, __) {
          // Retargets from the CURRENT colour when the settle lands a new
          // one, so back-to-back settles blend instead of restarting.
          return TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: tint ?? surface),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            builder: (context, animTint, __) {
              final t = animTint ?? surface;
              return DecoratedBox(
                decoration: BoxDecoration(
                  // Diagonal tint field: brighter top-left, deeper foot.
                  // TRANSLUCENT washes (not opaque lerps) since the glass
                  // stage landed: the blurred art behind glows through the
                  // colour, which is what makes the hero read glossy.
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(base, t, 0.55)!.withValues(alpha: 0.55),
                      Color.lerp(base, t, 0.40)!.withValues(alpha: 0.36),
                      Color.lerp(base, t, 0.25)!.withValues(alpha: 0.20),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
                child: DecoratedBox(
                  // Soft glow leaning toward the art region (right of centre)
                  // so the colour intensifies into it and the left stays calm
                  // for the title text.
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.55, -0.25),
                      radius: 1.3,
                      colors: [
                        Color.lerp(base, t, 0.62)!.withValues(alpha: 0.5),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

/// The idle key-art's edge dissolve — three eased feather shapes, TINTED
/// (lerped 0.34 toward the board bg) because at rest the art sits on the
/// coloured mood field. The live video paints the same shapes but NEUTRAL
/// and roughly half as wide (user call — heavy/tinted melt read as bleed
/// over the picture): by the time they fade in, the lights-off veils have
/// quenched the tint around the region, so slim near-black feathers land
/// seamlessly. Recolours only when the settled tint changes — never per
/// frame.
Widget buildHomeHeroArtFeathers({
  required Color base,
  ValueListenable<Color?>? tint,
}) {
  // Hoisted out of the builder below: the tint notifier fires on every
  // ambient artwork change, and an inherited-widget walk per tint frame is
  // exactly the hot path this board cannot afford on a TV box.
  return IgnorePointer(
    child: ValueListenableBuilder<Color?>(
      valueListenable: tint ?? const AlwaysStoppedAnimation<Color?>(null),
      builder: (context, tint, __) {
        final melt = tint == null ? base : Color.lerp(base, tint, 0.34)!;
        return Stack(
          fit: StackFit.expand,
          children: [
            homeHeroEdgeFeather(
              Alignment.centerLeft,
              Alignment.centerRight,
              melt,
              homeHeroTrailerFeatherFrac,
            ),
            homeHeroEdgeFeather(
              Alignment.topCenter,
              Alignment.bottomCenter,
              melt,
              0.16,
            ),
            homeHeroEdgeFeather(
              Alignment.bottomCenter,
              Alignment.topCenter,
              melt,
              0.36,
            ),
          ],
        );
      },
    ),
  );
}
