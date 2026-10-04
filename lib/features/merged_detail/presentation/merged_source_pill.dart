import 'package:debrify/features/merged_detail/presentation/merged_detail_palette.dart';
import 'package:debrify/features/merged_detail/presentation/merged_focus_halo.dart';
import 'package:flutter/material.dart';

class _SourcePill extends StatefulWidget {
  final int count;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  const _SourcePill({
    required this.count,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<_SourcePill> createState() => _SourcePillState();
}

class _SourcePillState extends State<_SourcePill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bound = widget.count > 0;
    const gold = MergedDetailPalette.gold;
    final label = bound
        ? (widget.count > 1 ? '${widget.count} sources' : '1 source')
        : 'Bind source';
    return MergedFocusHalo(
      focused: _focused,
      radius: BorderRadius.circular(999),
      child: Material(
        color: bound
            ? gold.withValues(alpha: 0.13)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(999),
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: bound
                    ? gold.withValues(alpha: 0.30)
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  bound ? Icons.link_rounded : Icons.link_off_rounded,
                  color: bound ? gold : Colors.white70,
                  size: 16,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: bound ? gold : Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
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

typedef MergedSourcePill = _SourcePill;

const mergedSourcePillConstructor = _SourcePill.new;
