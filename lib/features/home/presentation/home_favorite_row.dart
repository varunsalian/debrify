import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/material.dart';

/// Shared scaffold for a favourites row: a header (title + tag pills) above a
/// horizontal strip of poster-shaped cards, sized exactly like the catalog
/// rows so the whole board reads as one grid. [cellBuilder] gets the poster
/// width and full cell height (poster + title band) for each column.
Widget buildHomeFavoriteRow(
  BuildContext context, {
  required bool isTelevision,
  required double posterWidth,
  required double captionBand,
  required String title,
  required List<Widget> tags,
  required int itemCount,
  required Widget Function(int col, double posterW, double cellH) cellBuilder,
}) {
  final posterH = posterWidth * 3 / 2;
  // Reserve the inline caption band so a long title — e.g. a full release-name
  // playlist item — doesn't overflow the cell into the next section's header.
  final cellH = posterH + captionBand;
  final rowH = cellH + 14;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isTelevision ? 20 : 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            for (final t in tags) ...[const SizedBox(width: 6), t],
          ],
        ),
      ),
      SizedBox(
        height: rowH,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.hardEdge,
          scrollCacheExtent: const ScrollCacheExtent.pixels(400),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          itemCount: itemCount,
          itemBuilder: (context, col) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Center(
                child: SizedBox(
                  width: posterWidth,
                  height: cellH,
                  child: cellBuilder(col, posterWidth, cellH),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}
