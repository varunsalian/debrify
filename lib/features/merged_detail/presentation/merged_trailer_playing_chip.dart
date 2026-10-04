import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:flutter/material.dart';

/// Subtle "trailer playing in background" hint pill. An informational hint, not
/// a primary control (the focusable "Watch Trailer" button is the DPAD way to
/// promote), so it's pointer/touch-tappable only — `canRequestFocus: false`
/// keeps it out of DPAD traversal entirely, so it can never steal focus or
/// strand the remote when it appears/disappears as the trailer plays/pauses.
class _TrailerPlayingChip extends StatelessWidget {
  final VoidCallback onTap;

  /// Null for Classic.
  final DetailTheme? theme;

  const _TrailerPlayingChip({required this.onTap, this.theme});

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final radius = t?.brBtn ?? BorderRadius.circular(999);
    return Material(
      color:
          t?.ground.withValues(alpha: 0.6) ??
          Colors.black.withValues(alpha: 0.42),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        canRequestFocus: false,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: t?.hair ?? Colors.white.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 14,
                color: t?.tx ?? Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 7),
              Text(
                'Trailer playing',
                style: TextStyle(
                  color: t?.tx ?? Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef MergedTrailerPlayingChip = _TrailerPlayingChip;

const mergedTrailerPlayingChipConstructor = _TrailerPlayingChip.new;
