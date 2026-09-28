import 'package:flutter/widgets.dart';

/// Keyword list scroll lifetime and cinema return position. Result focus nodes
/// are borrowed from KeywordFocusController; no search state is copied here.
class KeywordViewport {
  final scroll = ScrollController();
  double lastOffset = 0;
  double? pendingOffset;
  int _cinemaIndex = 0;

  /// Register at the host's original initialization point. The last observed
  /// offset remains available after the list detaches for snapshot capture.
  void observeScroll() => scroll.addListener(_recordScroll);
  void _recordScroll() {
    if (scroll.hasClients) lastOffset = scroll.offset;
  }

  void restoreAfterLayout({
    required bool hasResults,
    required bool Function() isCurrent,
  }) {
    final offset = pendingOffset;
    if (offset == null || !hasResults) return;
    pendingOffset = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isCurrent() && scroll.hasClients) {
        scroll.jumpTo(offset.clamp(0.0, scroll.position.maxScrollExtent));
      }
    });
  }

  void resetSource() {
    _cinemaIndex = 0;
    pendingOffset = null;
    lastOffset = 0;
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  void focusResults(List<FocusNode> nodes, {required VoidCallback fallback}) {
    if (nodes.isEmpty) {
      fallback();
      return;
    }
    nodes[_cinemaIndex.clamp(0, nodes.length - 1)].requestFocus();
  }

  bool isSourceFocused(List<FocusNode> nodes, {required VoidCallback freeze}) {
    final index = nodes.indexWhere((node) => node.hasFocus);
    if (index >= 0) {
      _cinemaIndex = index;
      freeze();
    }
    return index >= 0;
  }

  void dispose() => scroll.dispose();
}
