import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Shared DPAD handling for a See-All filter bar: left/right walk the row of
/// [nodes]; down/up leave the bar via [onDown]/[onUp]. [onLeftEdge] (optional)
/// fires on Left at the first node — used embedded to escape to the TV sidebar;
/// omit it (standalone pushed screens) to swallow Left at the edge. Callers gate
/// on `isTelevision` before invoking. Returns a result for `Focus.onKeyEvent`.
KeyEventResult handleSeeAllFilterArrows(
  KeyEvent event,
  List<FocusNode> nodes, {
  required VoidCallback onDown,
  required VoidCallback onUp,
  VoidCallback? onLeftEdge,
}) {
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  final i = nodes.indexWhere((n) => n.hasFocus);
  if (i < 0) return KeyEventResult.ignored;
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.arrowLeft) {
    if (i > 0) {
      nodes[i - 1].requestFocus();
    } else {
      onLeftEdge?.call();
    }
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowRight) {
    if (i < nodes.length - 1) nodes[i + 1].requestFocus();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowDown) {
    onDown();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    onUp();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}
