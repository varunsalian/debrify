import 'dart:collection';
import 'package:flutter/widgets.dart';
import '../models/home_iptv_list.dart';

/// View-owned nodes retain list identity and channel position across reloads.
class HomeIptvListFocus {
  final _nodes = <String, List<FocusNode>>{};

  List<FocusNode> nodesFor(String listId) =>
      UnmodifiableListView(_nodes[listId] ?? const <FocusNode>[]);

  void reconcile(List<HomeIptvList> rows) {
    final retained = <String>{};
    for (final row in rows) {
      retained.add(row.listId);
      final nodes = _nodes.putIfAbsent(row.listId, () => []);
      while (nodes.length < row.channels.length) {
        nodes.add(
          FocusNode(
            debugLabel: 'search_iptvlist_${row.listId}_${nodes.length}',
          ),
        );
      }
      while (nodes.length > row.channels.length) {
        nodes.removeLast().dispose();
      }
    }
    for (final id
        in _nodes.keys.where((id) => !retained.contains(id)).toList()) {
      final nodes = _nodes.remove(id)!;
      for (final node in nodes) {
        node.dispose();
      }
      nodes.clear();
    }
  }

  void dispose() {
    for (final nodes in _nodes.values) {
      for (final node in nodes) {
        node.dispose();
      }
      nodes.clear();
    }
    _nodes.clear();
  }
}
