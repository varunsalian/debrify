import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

/// When a row's horizontal scroll gets within this many pixels of the end, the
/// next page for that catalog is fetched (Stremio-style unlimited rows).
const double _loadMoreThreshold = 900;

/// A classic catalog rail's header, lazy strip and paging notification boundary.
/// The host owns cells and actions. Read the child count when the inner Builder
/// builds, preserving the live legacy page/spinner count's evaluation point.
Widget buildHomeCatalogRow({
  required Widget header,
  required double cellHeight,
  required int Function() readChildCount,
  required IndexedWidgetBuilder itemBuilder,
  required VoidCallback onLoadMore,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    header,
    SizedBox(
      height: cellHeight + 14,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // Only this row's horizontal scroll reaches here; the vertical board
          // is an ancestor. Leave notifications available to existing ancestors.
          if (notification.metrics.axis == Axis.horizontal &&
              notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - _loadMoreThreshold) {
            onLoadMore();
          }
          return false;
        },
        child: Builder(
          builder: (context) => ListView.builder(
            scrollDirection: Axis.horizontal,
            // Clip cards scrolled past the sidebar, retaining vertical headroom
            // for the hover/focus lift. Cache the original 400 logical pixels.
            clipBehavior: Clip.hardEdge,
            scrollCacheExtent: const ScrollCacheExtent.pixels(400),
            padding: const EdgeInsets.symmetric(horizontal: 13),
            itemCount: readChildCount(),
            itemBuilder: itemBuilder,
          ),
        ),
      ),
    ),
  ],
);
