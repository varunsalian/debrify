import 'package:flutter/material.dart';

/// A relationship the tracker either holds or doesn't — rendered as a switch
/// so the current state is readable without parsing an "Add…"/"Remove…" verb.
class _SheetSwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final Color accent;
  final bool autofocus;
  final VoidCallback onTap;

  const _SheetSwitchRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.accent,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        autofocus: autofocus,
        focusColor: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 18, 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 21,
                color: value ? accent : Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // A drawn switch rather than a Material Switch: this is a
              // command that round-trips to an API, so it must not animate to
              // the new position before the call lands — the parent re-reads
              // the status and rebuilds with the truth.
              Container(
                width: 42,
                height: 24,
                decoration: BoxDecoration(
                  color: value ? accent : Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef MergedSheetSwitchRow = _SheetSwitchRow;

const mergedSheetSwitchRowConstructor = _SheetSwitchRow.new;
