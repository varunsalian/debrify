import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Generic DPAD arrow-handling wrapper for a favourites-row card — the arrow
/// counterpart to the catalog cell for IPTV / Debrify TV / Stremio TV rows.
/// Holds no focus itself — the child card does; this only routes
/// left/right within the row and up/down out of it, matching the catalog
/// cards' navigation exactly.
class HomeFavoriteCell extends StatelessWidget {
  final bool isTelevision;
  final int column;
  final List<FocusNode> rowNodes;
  final VoidCallback onUp;
  final VoidCallback onDown;

  /// Leaving the first card to the left (normally the TV sidebar).
  final VoidCallback onLeftEdge;

  /// Horizontal overrides. Null keeps neighbour/left-edge row navigation.
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  /// Held up/down overrides; null repeats the ordinary vertical action.
  final VoidCallback? onUpHold;
  final VoidCallback? onDownHold;
  final Widget child;

  const HomeFavoriteCell({
    super.key,
    required this.isTelevision,
    required this.column,
    required this.rowNodes,
    required this.onUp,
    required this.onDown,
    required this.onLeftEdge,
    this.onLeft,
    this.onRight,
    this.onUpHold,
    this.onDownHold,
    required this.child,
  });

  KeyEventResult _handleArrows(FocusNode node, KeyEvent event) {
    // Act on key-down AND key-repeat (held DPAD). If we let a repeat fall
    // through as `ignored`, Flutter's default geometric traversal fires and
    // jumps focus into an adjacent row — so only key-ups are passed on.
    if (!isTelevision || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (onLeft != null) {
        onLeft!();
      } else if (column > 0) {
        rowNodes[column - 1].requestFocus();
      } else {
        onLeftEdge();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (onRight != null) {
        onRight!();
      } else if (column < rowNodes.length - 1) {
        rowNodes[column + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (event is KeyRepeatEvent && onUpHold != null) {
        onUpHold!();
      } else {
        onUp();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyRepeatEvent && onDownHold != null) {
        onDownHold!();
      } else {
        onDown();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleArrows,
      child: child,
    );
  }
}
