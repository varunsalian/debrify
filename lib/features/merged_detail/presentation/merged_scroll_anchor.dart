import 'package:flutter/material.dart';

/// Auto-scrolls the enclosing scrollable when any descendant gains focus.
///
/// [Focus.onFocusChange] fires when this node *or a descendant* changes focus,
/// so wrapping a section with this (non-focusable, traversal-skipping) node
/// lets us react to a child button/tile being focused via DPAD:
///  • [toTop] snaps the column to offset 0 (reveals the header above the first
///    focusable — the "can't scroll back up to the details" fix);
///  • otherwise it `ensureVisible`s the wrapped section at [alignment].
class _ScrollAnchor extends StatelessWidget {
  final Widget child;
  final bool toTop;
  final double alignment;

  /// Only meaningful on TV (DPAD focus scroll). On pointer/desktop this is a
  /// passthrough so a mouse click doesn't yank the column around.
  final bool active;

  const _ScrollAnchor({
    required this.child,
    this.toTop = false,
    this.alignment = 0.5,
    this.active = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus) return;
        // Defer so it wins over the framework's own focus-ensureVisible and
        // runs after layout settles.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (toTop) {
            Scrollable.maybeOf(context)?.position.animateTo(
              0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          } else {
            Scrollable.ensureVisible(
              context,
              alignment: alignment,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          }
        });
      },
      child: child,
    );
  }
}

typedef MergedScrollAnchor = _ScrollAnchor;

const mergedScrollAnchorConstructor = _ScrollAnchor.new;
