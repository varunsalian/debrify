import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'home_stage_hold_latch.dart';

/// Navigation for one Mosaic cell. Nodes and the view's hold latch are borrowed;
/// count/columns retain the frame's geometry while nodes can grow with paging.
class HomeMosaicCellNavigation {
  const HomeMosaicCellNavigation({
    required this.column,
    required this.count,
    required this.perRow,
    required this.nodes,
    required this.hold,
    required this.focusSidebar,
    required this.switchRail,
    required this.loadMore,
    required this.deferRight,
  });

  final int column;
  final int count;
  final int perRow;
  final List<FocusNode> nodes;
  final HomeStageHoldLatch hold;
  final VoidCallback focusSidebar;
  final ValueChanged<int> switchRail;
  final VoidCallback? loadMore;
  final VoidCallback deferRight;

  void _prefetch() {
    // Two grid rows, matching the strip's six-card prefetch intent.
    if (column >= count - perRow * 2) loadMore?.call();
  }

  void _focusAt(int target) {
    if (target < 0 || target >= nodes.length) return;
    nodes[target].requestFocus();
  }

  void left() {
    if (column % perRow == 0) {
      focusSidebar();
    } else {
      _focusAt(column - 1);
    }
  }

  void right() {
    _prefetch();
    // Wrap to the next grid line while a cell exists. At a catalog boundary,
    // preserve the request until the page arrives through the host's scheduler.
    if (column + 1 < nodes.length) {
      _focusAt(column + 1);
    } else if (loadMore != null) {
      deferRight();
    }
  }

  void up() {
    if (hold.swallows(LogicalKeyboardKey.arrowUp)) return;
    if (column - perRow >= 0) {
      _focusAt(column - perRow);
    } else {
      switchRail(-1);
    }
  }

  void down() {
    if (hold.swallows(LogicalKeyboardKey.arrowDown)) return;
    _prefetch();
    if (column + perRow < count) {
      _focusAt(column + perRow);
    } else {
      // DOWN leaves the last line; pagination must never trap the user here.
      switchRail(1);
    }
  }

  void upHold() => hold.jump(LogicalKeyboardKey.arrowUp, () {
    switchRail(-1);
    return true;
  });

  void downHold() => hold.jump(LogicalKeyboardKey.arrowDown, () {
    switchRail(1);
    return true;
  });
}
