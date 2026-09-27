import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../../../models/stremio_addon.dart';
import 'home_board_cell.dart';
import 'home_stage_rows.dart';

/// A Continue Watching row — the same poster cards as the
/// catalog rows, plus a bottom progress bar and an optional type tag. Vertical
/// navigation and menu actions remain with the composing view.
Widget buildHomeContinuationRow({
  required HomeContinuationRow row,
  required Widget header,
  required bool isTelevision,
  required double posterWidth,
  required double cellHeight,
  required double Function() aspectRatio,
  required bool Function() showTitleOverlay,
  required String? Function(StremioMeta item) artOf,
  required bool Function(StremioMeta item) isBound,
  required VoidCallback onLeftEdge,
  required ValueChanged<StremioMeta> onFocused,
  required void Function(StremioMeta item, int column) onMenu,
  required ValueChanged<int> onUp,
  required ValueChanged<int> onDown,
}) {
  final rowH = cellHeight + 14;
  final items = row.items;
  final nodes = row.nodes;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      header,
      SizedBox(
        height: rowH,
        child: Builder(
          builder: (context) {
            // Rows start on the first poster (no leading See-All tile). DPAD-up
            // from the first CW row leaves the board; col-0 DPAD-left drops to
            // the sidebar through the caller's onLeftEdge action.
            return ListView.builder(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.hardEdge,
              scrollCacheExtent: const ScrollCacheExtent.pixels(400),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final col = index;
                final item = items[col];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  child: Center(
                    child: SizedBox(
                      width: posterWidth,
                      height: cellHeight,
                      child: HomeBoardCell(
                        onLeftEdge: onLeftEdge,
                        item: item,
                        isTelevision: isTelevision,
                        focusNode: nodes[col],
                        column: col,
                        rowNodes: nodes,
                        hasBoundSource: isBound(item),
                        // A Continue Watching progress bar describes the
                        // active viewing session. A global "watched once"
                        // check from another tracker reads as contradictory
                        // here, especially during a rewatch.
                        showWatchedBadge: false,
                        aspectRatio: aspectRatio(),
                        artUrl: artOf(item),
                        showTitleOverlay: showTitleOverlay(),
                        progress: row.progressOf(item),
                        episodeLabel: row.episodeOf(item),
                        // Long-press / hold-OK opens the Play + Remove menu
                        // rather than playing outright — a Continue Watching
                        // card is the one place removal has to be reachable.
                        onLongPress: () => onMenu(item, col),
                        onFocused: () => onFocused(item),
                        onUp: () => onUp(col),
                        onDown: () => onDown(col),
                        onOpen: () => row.onOpen(item),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );
}
