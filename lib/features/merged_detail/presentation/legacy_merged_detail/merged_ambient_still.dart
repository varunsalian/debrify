import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:flutter/material.dart';

/// The focused episode's frame, painted over the title artwork.
///
/// Switches instantly on TV: a fullscreen animated opacity per DPAD move is
/// exactly what the TV cost budget forbids. Off-TV it cross-fades.
class _AmbientStill extends StatelessWidget {
  final String url;
  final bool isTelevision;

  const _AmbientStill({required this.url, required this.isTelevision});

  @override
  Widget build(BuildContext context) {
    final image = CachedNetworkImage(
      key: ValueKey(url),
      imageUrl: url,
      fit: BoxFit.cover,
      cacheManager: DebrifyImageCache.manager,
      memCacheWidth: 1280,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) => const SizedBox.shrink(),
    );
    if (isTelevision) return image;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      // The default layout centres children under LOOSE constraints, so a
      // BoxFit.cover image would size itself to its own aspect and letterbox.
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: image,
    );
  }
}

typedef MergedAmbientStill = _AmbientStill;

const mergedAmbientStillConstructor = _AmbientStill.new;
