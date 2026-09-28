import 'package:flutter/material.dart';
import '../../../models/home_collection_rows.dart';
import '../../../models/stremio_addon.dart';
import 'home_board_cell.dart';
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

/// Render catalog/collection cells against the borrowed section's live items.
/// The host supplies navigation and accepted actions without owning cell layout.
Widget buildHomeCatalogItems({
  required CatalogSection section,
  required List<FocusNode> nodes,
  required bool tv,
  required Widget header,
  required double cellH,
  required double cellAspect,
  required double posterW,
  required String Function(int) heroTagFor,
  required bool Function(StremioMeta) isBound,
  required String? Function(StremioMeta) artOf,
  required bool Function() showTitle,
  required bool Function() pikpakOnly,
  required VoidCallback onLeftEdge,
  required VoidCallback Function(int) up,
  required VoidCallback Function(int) down,
  required void Function(StremioMeta, int) onFocused,
  required void Function(StremioMeta, String) onOpen,
  required ValueChanged<StremioMeta> onQuickPlay,
  required VoidCallback onLoadMore,
}) {
  final collection = section is HomeCollectionSection ? section : null;
  return buildHomeCatalogRow(
    header: header,
    cellHeight: cellH,
    readChildCount: () => section.items.length + (section.loadingMore ? 1 : 0),
    onLoadMore: onLoadMore,
    itemBuilder: (context, index) {
      final col = index;
      if (col >= section.items.length) {
        return SizedBox(
          width: 52,
          height: cellH,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      final item = section.items[col];
      final itemAspect = collection?.tileAspectOf(item) ?? cellAspect;
      // Unique per cell AND per SearchScreen instance (Home,
      // Discover and Search coexist in the tab stack — a shared
      // tag across them would trip Hero's duplicate-tag assert).
      final heroTag = heroTagFor(col);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11),
        child: Center(
          child: SizedBox(
            width: collection == null ? posterW : cellH * itemAspect,
            height: cellH,
            child: HomeBoardCell(
              onLeftEdge: onLeftEdge,
              item: item,
              isTelevision: tv,
              focusNode: nodes[col],
              column: col,
              rowNodes: nodes,
              hasBoundSource: isBound(item),
              aspectRatio: itemAspect,
              artUrl: collection != null ? item.poster : artOf(item),
              focusArtUrl: collection?.focusArtOf(item),
              focusVideoUrl: collection?.focusVideoOf(item),
              focusGlowEnabled:
                  collection?.collection.focusGlowEnabled ?? false,
              showTitleOverlay: collection != null
                  ? !(collection.folderOf(item)?.hideTitle ?? false)
                  : showTitle(),
              onQuickPlay: pikpakOnly() || collection != null
                  ? null
                  : () => onQuickPlay(item),
              onFocused: () {
                onFocused(item, col);
              },
              onUp: up(col),
              onDown: down(col),
              onOpen: () => onOpen(item, heroTag),
              onNearEnd: () => onLoadMore(),
              heroTag: heroTag,
            ),
          ),
        ),
      );
    },
  );
}
