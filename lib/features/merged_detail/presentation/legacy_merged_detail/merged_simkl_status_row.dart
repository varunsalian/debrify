import 'package:debrify/widgets/tracker_brand_marks.dart';
import 'package:flutter/material.dart';

/// One of Simkl's five mutually-exclusive list switches. The whole row is the
/// DPAD stop; the nested switch is excluded from focus so TV navigation still
/// costs one press per status.
class _SimklStatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool autofocus;

  /// Never null so every row remains focusable after a state transition.
  final VoidCallback onTap;

  const _SimklStatusRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(11);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected
            ? kSimklCyan.withValues(alpha: 0.13)
            : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          autofocus: autofocus,
          borderRadius: radius,
          focusColor: Colors.white.withValues(alpha: 0.12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? kSimklCyan.withValues(alpha: 0.35)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: selected
                      ? kSimklCyan
                      : Colors.white.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? kSimklCyan : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ExcludeFocus(
                  child: Switch.adaptive(
                    value: selected,
                    activeThumbColor: kSimklCyan,
                    activeTrackColor: kSimklCyan.withValues(alpha: 0.42),
                    onChanged: (_) => onTap(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

typedef MergedSimklStatusRow = _SimklStatusRow;

const mergedSimklStatusRowConstructor = _SimklStatusRow.new;
