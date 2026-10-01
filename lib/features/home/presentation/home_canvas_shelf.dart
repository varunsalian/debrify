import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/widgets.dart';

/// Canvas's lazy horizontal shelf. Return the ListView directly so the owning
/// AnimatedSwitcher still sees its original rail key and widget type.
///
/// The caller supplies card contents and owns all focus and action callbacks.
/// Favourite cards keep their intrinsic height; catalog/CW cards use the given
/// fixed art height. Both remain centered in the shared shelf/caption band.
Widget buildHomeCanvasShelf({
  required String railKey,
  required int itemCount,
  required double cardWidth,
  required double? cardHeight,
  required IndexedWidgetBuilder itemBuilder,
}) => ListView.builder(
  // Insertions above the active rail must never look like a content swap.
  key: ValueKey('canvas-rail-$railKey'),
  scrollDirection: Axis.horizontal,
  clipBehavior: Clip.hardEdge,
  scrollCacheExtent: const ScrollCacheExtent.pixels(400),
  padding: const EdgeInsets.symmetric(horizontal: 48),
  itemCount: itemCount,
  itemBuilder: (context, col) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 7),
    // Split vertical slack so focus scale-up is not clipped at the top edge.
    child: Center(
      child: SizedBox(
        width: cardWidth,
        height: cardHeight,
        child: itemBuilder(context, col),
      ),
    ),
  ),
);
