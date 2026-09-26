import 'dart:collection';

import 'package:flutter/widgets.dart';

/// Owned by one Sources view. Rows borrow nodes through a read-only live list.
class SourceRowFocusNodes {
  final _nodes = <FocusNode>[];
  late final List<FocusNode> nodes = UnmodifiableListView(_nodes);
  bool _disposed = false;

  void _grow(int count) {
    while (_nodes.length < count) {
      _nodes.add(FocusNode(debugLabel: 'src_${_nodes.length}'));
    }
  }

  /// Search switches to its loading view and retires the prior nodes immediately.
  void resetForSearch() {
    if (_disposed) return;
    for (final node in _nodes) {
      node.dispose();
    }
    _nodes.clear();
  }

  /// Streaming retains existing positions. Removed rows detach on the next frame.
  void resize(int count) {
    if (_disposed) return;
    assert(count >= 0);
    _grow(count);
    if (_nodes.length > count) {
      final removed = <FocusNode>[];
      var removedFocus = false;
      while (_nodes.length > count) {
        final node = _nodes.removeLast();
        removedFocus = removedFocus || node.hasFocus;
        removed.add(node);
      }
      // Focus requests apply asynchronously. An intermediate last node could
      // itself be removed by this resize, so choose the final survivor once.
      if (removedFocus && _nodes.isNotEmpty) _nodes.last.requestFocus();
      _retireAfterFrame(removed);
    }
  }

  /// Toolbar changes replace nodes without moving focus away from the toolbar.
  void replaceAll(int count) {
    if (_disposed) return;
    assert(count >= 0);
    final old = List<FocusNode>.of(_nodes);
    _nodes.clear();
    _grow(count);
    _retireAfterFrame(old);
  }

  void _retireAfterFrame(List<FocusNode> retired) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final node in retired) {
        node.dispose();
      }
    });
  }

  void dispose() {
    if (_disposed) return;
    resetForSearch();
    _disposed = true;
  }
}
