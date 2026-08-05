import 'package:flutter/material.dart';

import '../../../services/skip_segment_service.dart';

/// The OTT skip action ("Skip intro »") as a small squared chip, Netflix-style
/// — near-black glass, crisp light border, no icon — matching the native TV
/// player's chip so the two players speak one visual language.
///
/// Sizing adapts to the surface: compact on phones, a step larger where
/// there's room (tablet / desktop windows), keyed off the window's shortest
/// side rather than platform so a resizable desktop window behaves sensibly
/// at any size. Pointer devices get hover/press ink; keyboard focus gets the
/// same overlay through the InkWell's focus state.
class SkipSegmentButton extends StatelessWidget {
  final SkipSegmentType type;
  final VoidCallback onPressed;

  const SkipSegmentButton({
    super.key,
    required this.type,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isIntro = type == SkipSegmentType.intro;
    final label = isIntro ? 'Skip intro' : 'Skip credits';
    // Phones (shortest side < 600) get the compact cut; tablets and desktop
    // windows the comfortable one. A desktop window dragged small gracefully
    // falls back to compact.
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;

    return Semantics(
      button: true,
      label: label,
      child: Container(
        key: const ValueKey('skip-segment-button'),
        decoration: BoxDecoration(
          color: const Color(0xD9101014),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(3),
            // No ripple: a quiet chip over video should tint, not sparkle.
            // (Also keeps the widget free of the M3 ink shader, which the
            // test harness can't load.)
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return Colors.white.withValues(alpha: 0.18);
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return Colors.white.withValues(alpha: 0.10);
              }
              return null;
            }),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 16,
                vertical: compact ? 7 : 9,
              ),
              child: Text(
                '$label »',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 12.5 : 13.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
