import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/tv_keys.dart';

/// One mounted Keyword surface's focus resources and keyboard navigation.
/// Application state and cross-surface targets remain callbacks, not copied state.
class KeywordFocusController {
  KeywordFocusController({
    required this.focusSearch,
    required this.focusSidebar,
    required this.focusAboveToolbar,
    required this.hasAccessibleArrivals,
  });
  final VoidCallback focusSearch, focusSidebar, focusAboveToolbar;
  final bool Function() hasAccessibleArrivals;
  final List<FocusNode> rows = [];
  final List<FocusNode> tabs = [];
  final List<FocusNode> toolbar = List.generate(
    5,
    (i) => FocusNode(debugLabel: 'kw_tb_$i'),
  );
  final FocusNode arrivals = FocusNode(debugLabel: 'kw_pill');
  final FocusNode sources = FocusNode(debugLabel: 'kw_sources_btn');
  bool _disposed = false;

  void syncRows(int length) => _sync(rows, length, 'kw_');
  void syncTabs(int sourceCount) => _sync(tabs, sourceCount + 1, 'kw_tab_');

  void _sync(List<FocusNode> nodes, int length, String label) {
    if (_disposed) return;
    while (nodes.length < length) {
      nodes.add(FocusNode(debugLabel: '$label${nodes.length}'));
    }
    if (nodes.length <= length) return;
    final removed = <FocusNode>[];
    while (nodes.length > length) {
      final node = nodes.removeLast();
      if (node.hasFocus && nodes.isNotEmpty) nodes.last.requestFocus();
      removed.add(node);
    }
    // Removed rows/tabs are still mounted this frame. Always release their
    // nodes after unmount, even if the owning route retires before the callback.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final node in removed) {
        node.dispose();
      }
    });
  }

  /// Immediate reset is used only where the original route cleared a query or
  /// restored a snapshot; live result changes use deferred disposal in syncRows.
  void clearRows() {
    for (final node in rows) {
      node.dispose();
    }
    rows.clear();
  }

  void focusTab(int index) {
    if (_disposed || index < 0 || index >= tabs.length) return;
    final node = tabs[index];
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!_disposed && context != null && context.mounted) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 120),
        );
      }
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    arrivals.dispose();
    sources.dispose();
    for (final node in tabs) {
      node.dispose();
    }
    tabs.clear();
    clearRows();
    for (final node in toolbar) {
      node.dispose();
    }
    toolbar.clear();
  }

  KeyEventResult handleTabKey(
    int index,
    int total,
    VoidCallback onTap,
    KeyEvent event,
  ) {
    if (_disposed || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      onTap();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      focusSearch();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      toolbar.first.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        focusTab(index - 1);
      } else {
        focusSidebar();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (index < total - 1) focusTab(index + 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult handleToolbarKey(
    int index,
    int total,
    VoidCallback onTap,
    KeyEvent event,
  ) {
    if (_disposed || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      onTap();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      focusAboveToolbar();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (rows.isNotEmpty) {
        rows.first.requestFocus();
      } else if (hasAccessibleArrivals()) {
        // Zero rows (e.g. a no-match filter) but arrivals parked behind the
        // pill: the pill must stay reachable or it's visible-but-dead on TV.
        arrivals.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        toolbar[index - 1].requestFocus();
      } else {
        focusSidebar();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (index < total - 1) toolbar[index + 1].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
