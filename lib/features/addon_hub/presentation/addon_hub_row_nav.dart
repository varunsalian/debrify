import 'package:flutter/material.dart';

/// A grow-only pool of focus nodes, one per focusable marketplace row, used to
/// hop DPAD focus row-to-row deterministically. Grow-only (never disposes mid-
/// session) so a shrinking filtered list can't dispose a node that holds focus.
class AddonHubRowNav {
  final List<FocusNode> _nodes = [];

  void ensure(int n) {
    while (_nodes.length < n) {
      _nodes.add(FocusNode(debugLabel: 'market-row-${_nodes.length}'));
    }
  }

  FocusNode? nodeAt(int i) => (i >= 0 && i < _nodes.length) ? _nodes[i] : null;

  /// Focus row [i] if it exists; returns whether it did.
  bool focus(int i) {
    final node = nodeAt(i);
    if (node == null) return false;
    node.requestFocus();
    return true;
  }

  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    _nodes.clear();
  }
}
