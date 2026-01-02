import 'package:flutter/material.dart';

/// Wraps a focusable widget to ensure proper scroll positioning on Android TV.
///
/// When a descendant widget gains focus, this wrapper ensures the item is
/// scrolled into view with appropriate padding from the top (to avoid being
/// hidden behind AppBar/headers).
///
/// This fixes an issue where D-pad navigation up would scroll the first item
/// behind the AppBar because Flutter's default alignment is 0.0 (top of viewport).
class TvFocusScrollWrapper extends StatelessWidget {
  final Widget child;

  /// Alignment for scroll positioning (0.0 = top, 0.5 = center, 1.0 = bottom).
  /// Default is 0.2 to keep ~20% padding from top, accounting for headers.
  final double alignment;

  /// Duration for scroll animation.
  final Duration duration;

  const TvFocusScrollWrapper({
    super.key,
    required this.child,
    this.alignment = 0.2,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      // Don't intercept focus - just observe descendant focus changes
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          // Ensure this item is visible with proper alignment
          Scrollable.ensureVisible(
            context,
            alignment: alignment,
            duration: duration,
            curve: Curves.easeOutCubic,
          );
        }
      },
      child: child,
    );
  }
}
