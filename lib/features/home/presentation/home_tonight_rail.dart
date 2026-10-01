import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/widgets.dart';

import 'home_tonight_layout.dart'
    show homeTonightHorizontalPadding, homeTonightRailTail;

/// Tonight's label and lazy horizontal rail. Selection, borrowed focus nodes,
/// per-kind cell geometry and actions stay with the caller's indexed builder.
Widget buildHomeTonightRail({
  required double railHeight,
  required double labelGap,
  required String railKey,
  required int itemCount,
  required Widget label,
  required IndexedWidgetBuilder itemBuilder,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(right: homeTonightHorizontalPadding),
        child: label,
      ),
      SizedBox(height: labelGap),
      SizedBox(
        height: railHeight,
        child: ListView.builder(
          key: ValueKey('tonight-rail-$railKey'),
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.hardEdge,
          scrollCacheExtent: const ScrollCacheExtent.pixels(400),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        ),
      ),
      const SizedBox(height: homeTonightRailTail),
    ],
  );
}
