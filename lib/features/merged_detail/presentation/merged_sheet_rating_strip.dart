import 'package:flutter/material.dart';

/// The 1–10 rating strip. Ten focusable cells beat a modal dialog on both
/// inputs: one tap on touch, a LEFT/RIGHT run and OK on a remote.
class _SheetRatingStrip extends StatelessWidget {
  final int? rating;
  final Color accent;
  final Color onAccent;
  final void Function(int rating) onRate;
  final VoidCallback? onClear;

  /// Puts the DPAD cursor on the current score (or 1 when unrated) — used when
  /// the strip is the first thing in the sheet.
  final bool autofocus;

  const _SheetRatingStrip({
    required this.rating,
    required this.accent,
    required this.onAccent,
    required this.onRate,
    this.onClear,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final current = rating;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 1; i <= 10; i++) ...[
                if (i > 1) const SizedBox(width: 5),
                Expanded(
                  child: Material(
                    color: current == null || i > current
                        ? Colors.white.withValues(alpha: 0.07)
                        : (i == current
                              ? accent
                              : accent.withValues(alpha: 0.22)),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      autofocus: autofocus && i == (current ?? 1),
                      borderRadius: BorderRadius.circular(8),
                      focusColor: Colors.white.withValues(alpha: 0.18),
                      onTap: () => onRate(i),
                      child: SizedBox(
                        height: 32,
                        child: Center(
                          child: Text(
                            '$i',
                            style: TextStyle(
                              color: current != null && i == current
                                  ? onAccent
                                  : Colors.white.withValues(
                                      alpha: current != null && i < current
                                          ? 0.85
                                          : 0.5,
                                    ),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                current != null ? 'Rated $current/10' : 'Not rated',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12.5,
                ),
              ),
              const Spacer(),
              if (onClear != null)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    focusColor: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    onTap: onClear,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        'Clear rating',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

typedef MergedSheetRatingStrip = _SheetRatingStrip;

const mergedSheetRatingStripConstructor = _SheetRatingStrip.new;
