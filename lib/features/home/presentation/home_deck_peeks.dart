import 'package:flutter/widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/stremio_addon.dart';
import '../application/home_stage_metadata.dart';
import 'home_deck_layout.dart' show homeDeckCardRadius;

/// The two cards stacked behind the hero — the NEXT two titles on this
/// rail, drawn from the focused column so moving along the rail deals them
/// forward. Static art, no focus, no video.
List<Widget> buildHomeDeckPeeks({
  required List<StremioMeta> items,
  required bool favRail,
  required int focused,
  required double left,
  required double top,
  required double width,
  required double height,
}) {
  // Favourites rails have no StremioMeta to draw from — the deck simply
  // shows the single card, which is correct: a favourite has no "next".
  if (favRail || items.isEmpty) return const [];
  final at = focused.clamp(0, items.length - 1);
  final peeks = <Widget>[];
  // Painted far-to-near so the nearer card overlaps the farther one.
  for (final spec in const [
    (step: 2, dx: 0.19, scale: 0.87, alpha: 0.30),
    (step: 1, dx: 0.10, scale: 0.94, alpha: 0.52),
  ]) {
    final i = at + spec.step;
    if (i >= items.length) continue;
    final art = homeStageWideArtwork(items[i]);
    if (art == null || art.isEmpty) continue;
    peeks.add(
      Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: spec.alpha,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: AnimatedSlide(
              offset: Offset(spec.dx, 0),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: Transform.scale(
                scale: spec.scale,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(homeDeckCardRadius),
                  child: CachedNetworkImage(
                    key: ValueKey('deck-peek-${spec.step}-$art'),
                    imageUrl: art,
                    fit: BoxFit.cover,
                    memCacheWidth: 480,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  return peeks;
}
