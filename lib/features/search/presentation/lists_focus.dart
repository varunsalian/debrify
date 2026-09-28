import 'package:flutter/widgets.dart';

/// Search Lists owns result nodes; the current result identity lookup is borrowed
/// so returning from a covering route restores the list's current position.
class ListsFocus {
  final nodes = <FocusNode>[];

  void resize(int count) {
    while (nodes.length < count) {
      nodes.add(FocusNode(debugLabel: 'lists_row_${nodes.length}'));
    }
    while (nodes.length > count) {
      nodes.removeLast().dispose();
    }
  }

  void clear() {
    for (final node in nodes) {
      node.dispose();
    }
    nodes.clear();
  }

  void restore({
    required bool Function() isCurrent,
    required int Function() indexOfResult,
  }) {
    if (!isCurrent()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isCurrent()) return;
      final index = indexOfResult();
      if (index >= 0 && index < nodes.length) nodes[index].requestFocus();
    });
  }
}
