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

/// Owns continuation action nodes and their borrowed return-focus target.
class HomeContinuationFocus {
  final continueNode = FocusNode(debugLabel: 'catalog_continue');
  final moreNode = FocusNode(debugLabel: 'catalog_more');
  FocusNode? _origin;

  bool focusAction() {
    final target = [continueNode, moreNode]
        .where(
          (node) => node.parent != null && (node.context?.mounted ?? false),
        )
        .firstOrNull;
    if (target == null) return false;
    final origin = FocusManager.instance.primaryFocus;
    if (!identical(origin, target)) _origin = origin;
    target.requestFocus();
    return true;
  }

  bool restore(Iterable<FocusNode?> candidates) =>
      focusMountedHomeNode([_origin, ...candidates]);

  /// A removed action yields focus only if the user has not moved elsewhere.
  void restoreAfterCompletion(
    FocusNode actionNode, {
    required bool ownedFocus,
    required bool Function() isCurrent,
    required VoidCallback onRestore,
  }) {
    if (!isCurrent() || !ownedFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isCurrent()) return;
      if (actionNode.parent != null && (actionNode.context?.mounted ?? false)) {
        return;
      }
      final focused = FocusManager.instance.primaryFocus;
      if (focused != null && focused is! FocusScopeNode) return;
      onRestore();
    });
  }

  void dispose() {
    continueNode.dispose();
    moreNode.dispose();
  }
}
