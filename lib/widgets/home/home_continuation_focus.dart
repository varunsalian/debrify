import 'package:flutter/widgets.dart';

/// Restores focus without requesting an offstage or disposed rail's nodes.
/// Candidates are ordered by preference: the origin, active stage, then any
/// other mounted Home card. False lets the caller fall back to the sidebar.
bool focusMountedHomeNode(Iterable<FocusNode?> candidates) {
  for (final node in candidates) {
    if (node == null ||
        node.parent == null ||
        !(node.context?.mounted ?? false) ||
        !node.canRequestFocus) {
      continue;
    }
    node.requestFocus();
    return true;
  }
  return false;
}
