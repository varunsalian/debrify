import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:debrify/services/debrify_image_cache.dart'
    show DebrifyImageCache;
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

/// The bed the ambient field is laid on, and the veil over it.
///
/// **Darkens regardless of the ground, and that is not an oversight.** The
/// field is a bed for WHITE text — every band title, episode caption and
/// synopsis on this page is `_ink`, a hardcoded white — so a veil that followed
/// a pale ground would be a translucent white wash under white type.
///
/// Making it follow properly means the text following the ink first, which is
/// the same outstanding work `kDetailThemesShipped` documents when it withholds
/// `broadsheet` and `concrete`. Until that lands, the honest thing is a bed
/// that keeps its own text readable rather than one that tracks a setting and
/// breaks.
Color _ambientBed(AppTheme app) =>
    Color.lerp(app.home.bg, const Color(0xFF000000), 0.55)!;

// ── grounds ────────────────────────────────────────────────────────────────

/// The scrolled ground: the same artwork as a low-frequency colour field.
///
/// Decoded at 32px and scaled up rather than blurred. A real
/// `ImageFilter.blur(sigma: 45)` is a full-resolution Gaussian on every
/// repaint; a 32px decode is the same low-frequency information for
/// effectively nothing, and it is a still image so it repaints only when the
/// URL changes.
class ShowcaseAmbient extends StatelessWidget {
  final String? url;
  final bool visible;

  const ShowcaseAmbient({super.key, required this.url, required this.visible});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return const SizedBox.shrink();
    final bed = _ambientBed(AppThemeScope.of(context));
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOut,
      opacity: visible ? 1 : 0,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform.scale(
            scale: 1.15,
            child: CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              cacheManager: DebrifyImageCache.manager,
              memCacheWidth: 32,
              filterQuality: FilterQuality.low,
              placeholder: (_, __) => ColoredBox(color: bed),
              errorWidget: (_, __, ___) => ColoredBox(color: bed),
            ),
          ),
          // The field is a BED for white text, not a picture. Under a .55 veil
          // the artwork starts competing with the episode titles sitting on it.
          ColoredBox(color: bed.withValues(alpha: 0.58)),
        ],
      ),
    );
  }
}

/// The identity scrim: a 100° left fade, so the text side is dark and the art
/// keeps its right two-thirds.
class ShowcaseBackdropScrim extends StatelessWidget {
  final bool visible;

  /// The ambient trailer is rolling: pull the bed in tight so the video
  /// plays clear, keeping only what text legibility strictly needs — the
  /// same move the home hero makes while its picture rolls. Never true on
  /// TV (the page passes it only when `dpad` is false).
  final bool thinned;

  const ShowcaseBackdropScrim({
    super.key,
    required this.visible,
    this.thinned = false,
  });

  @override
  Widget build(BuildContext context) {
    // Two different jobs on two form factors. Wide: the identity sits at the
    // LEFT, so the bed is a diagonal sweep and the art's right half stays
    // clear. Compact: the identity is a centered stack at the FOOT, and that
    // same diagonal just washes the whole portrait frame grey — the art is
    // narrow, so "68% across" is everything. The phone scrim is vertical: a
    // light cap for the status bar, clear art through the middle, and a bed
    // under the identity text only.
    final compact = ShowcaseMetrics.of(context).compact;
    final gradient = compact
        ? (thinned
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x2E000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0x66000000),
                    Color(0xA8000000),
                  ],
                  stops: [0, 0.14, 0.6, 0.86, 1],
                )
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0xB3000000),
                    Color(0xE6000000),
                  ],
                  stops: [0, 0.18, 0.42, 0.78, 1],
                ))
        : (thinned
              ? const LinearGradient(
                  begin: Alignment(-1, -0.2),
                  end: Alignment(1, 0.2),
                  colors: [
                    Color(0x9E000000),
                    Color(0x66000000),
                    Color(0x1C000000),
                    Color(0x00000000),
                  ],
                  stops: [0, 0.26, 0.52, 0.68],
                )
              : const LinearGradient(
                  begin: Alignment(-1, -0.2),
                  end: Alignment(1, 0.2),
                  colors: [
                    Color(0xE0000000),
                    Color(0xA8000000),
                    Color(0x2E000000),
                    Color(0x00000000),
                  ],
                  stops: [0, 0.26, 0.52, 0.68],
                ));
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 550),
        opacity: visible ? 1 : 0,
        child: DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
      ),
    );
  }
}

/// The logo re-forming as a centred header once you descend.
class ShowcaseStickyLogo extends StatelessWidget {
  final String? url;
  final String name;
  final bool visible;

  const ShowcaseStickyLogo({
    super.key,
    required this.url,
    required this.name,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        opacity: visible ? 1 : 0,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          offset: visible ? Offset.zero : const Offset(0, -0.25),
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 22),
              child: (url == null || url!.isEmpty)
                  ? Text(name, style: st(17 * m.k, w: FontWeight.w700))
                  : CachedNetworkImage(
                      imageUrl: url!,
                      height: 37 * m.k,
                      fit: BoxFit.contain,
                      cacheManager: DebrifyImageCache.manager,
                      // Decode cap follows the k-scaled display size, or the
                      // one scaled element of the header renders soft.
                      memCacheWidth: (420 * m.k).round(),
                      errorWidget: (_, __, ___) =>
                          Text(name, style: st(17 * m.k, w: FontWeight.w700)),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
