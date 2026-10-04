import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a rail's end cards: consumes LEFT on the first / RIGHT on the last so
/// the DPAD cursor stops at the rail's edge instead of escaping to whatever is
/// geometrically nearest (the episodes pane, the back button). A non-focusable
/// ancestor node sees the key on its way up from the focused card, before the
/// app-level shortcuts turn it into a traversal move.
class _RailEdgeTrap extends StatelessWidget {
  final bool trapLeft;
  final bool trapRight;
  final Widget child;

  /// When set, RIGHT on the last card invokes this (pane crossing) instead of
  /// dead-stopping.
  final VoidCallback? onTrapRight;

  const _RailEdgeTrap({
    required this.trapLeft,
    required this.trapRight,
    required this.child,
    this.onTrapRight,
  });

  @override
  Widget build(BuildContext context) {
    if (!trapLeft && !trapRight) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (trapLeft && key == LogicalKeyboardKey.arrowLeft) {
          return KeyEventResult.handled;
        }
        if (trapRight && key == LogicalKeyboardKey.arrowRight) {
          onTrapRight?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

typedef MergedRailEdgeTrap = _RailEdgeTrap;

const mergedRailEdgeTrapConstructor = _RailEdgeTrap.new;
