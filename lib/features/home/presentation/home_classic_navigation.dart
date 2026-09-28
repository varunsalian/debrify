import 'package:flutter/widgets.dart';
import 'home_stage_rows.dart';

/// Classic's vertical traversal over the current globally ordered Home rows.
/// All nodes and row snapshots are borrowed; the host owns frame scheduling.
class HomeClassicNavigation {
  const HomeClassicNavigation({
    required this.rails,
    required this.rowIdOf,
    required this.nodesFor,
    required this.requestFocus,
    required this.leaveTop,
    required this.loadingMore,
    required this.hasMore,
    required this.focusContinuation,
    required this.loadMore,
    required this.deferDown,
  });

  final List<HomeRail> Function() rails;
  final String Function(HomeRail) rowIdOf;
  final List<FocusNode> Function(HomeRail) nodesFor;
  final void Function(List<FocusNode>, int) requestFocus;
  final VoidCallback leaveTop;
  final bool Function() loadingMore;
  final bool Function() hasMore;
  final bool Function() focusContinuation;
  final VoidCallback loadMore;
  final void Function(String rowId, int column) deferDown;

  bool focusAt(int index, int column) {
    final current = rails();
    if (index < 0 || index >= current.length) return false;
    final nodes = nodesFor(current[index]);
    if (nodes.isEmpty) return false;
    requestFocus(nodes, column.clamp(0, nodes.length - 1));
    return true;
  }

  /// Resolve by identity on each press: asynchronous rows can insert anywhere.
  void move(String rowId, int delta, int column) {
    final currentRails = rails();
    final current = currentRails.indexWhere((rail) => rowIdOf(rail) == rowId);
    if (current < 0) return;
    for (
      var i = current + delta;
      i >= 0 && i < currentRails.length;
      i += delta
    ) {
      if (focusAt(i, column)) return;
    }
    if (delta < 0) {
      leaveTop();
      return;
    }
    if (!loadingMore() && focusContinuation()) return;
    if (hasMore()) loadMore();
    deferDown(rowId, column);
  }
}
