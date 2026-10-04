import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:flutter/material.dart';

/// Logo art when it exists and is light enough to see; the title otherwise.
class SpotlightBoardLogoOrTitle extends StatelessWidget {
  final String? url;
  final String name;
  final TextAlign align;

  /// `_M.k` — 1.0 on TV and compact, the wide-touch correction elsewhere.
  final double scale;

  const SpotlightBoardLogoOrTitle({
    required this.url,
    required this.name,
    required this.align,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      maxLines: 2,
      textAlign: align,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 39 * scale,
        height: 1,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: Colors.white,
      ),
    );
    if (url == null || url!.isEmpty) return text;
    final corner = align == TextAlign.right
        ? Alignment.bottomRight
        : align == TextAlign.center
        ? Alignment.bottomCenter
        : Alignment.bottomLeft;
    // A RESERVED slot, not a maximum.
    //
    // This was a `ConstrainedBox(maxWidth: 235, maxHeight: 60)`, which sizes
    // itself to whatever is inside it. Before the art lands there is nothing
    // inside it, so the slot collapsed and the identity below sat higher up;
    // when the logo arrived a second or two later the block reflowed and
    // everything settled into a different place. The column is anchored by its
    // BOTTOM, so the whole identity moved, not just the logo.
    //
    // Holding the box at full size from the first frame means the art fades
    // into a space already shaped for it and nothing else moves.
    return SizedBox(
      width: 235 * scale,
      height: 60 * scale,
      child: CachedNetworkImage(
        imageUrl: url!,
        fit: BoxFit.contain,
        alignment: corner,
        cacheManager: DebrifyImageCache.manager,
        memCacheWidth: 520,
        placeholder: (_, __) => const SizedBox.shrink(),
        // The title has to earn its way into the same slot rather than
        // resizing it — scaleDown only shrinks, so short titles keep their
        // intended weight.
        //
        // The inner width is what makes that bearable: FittedBox offers its
        // child unbounded width, so without it `maxLines: 2` never wraps and a
        // long title is scaled down as one very long line.
        errorWidget: (_, __, ___) => Align(
          alignment: corner,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: corner,
            child: SizedBox(width: 235 * scale, child: text),
          ),
        ),
      ),
    );
  }
}
