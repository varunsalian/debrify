import 'package:flutter/material.dart';

import 'detail_style.dart';
import 'theme/detail_theme.dart';

/// A tracker's identity, live state and rating in one control.
class DetailTrackerPill extends StatefulWidget {
  final Widget mark;
  final String brand;
  final String state;
  final int? rating;
  final Color accent;
  final bool tracked;

  /// Drops the brand eyebrow — for narrow columns where it costs more than it
  /// tells.
  final bool compact;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  const DetailTrackerPill({
    super.key,
    required this.mark,
    required this.brand,
    required this.state,
    required this.rating,
    required this.accent,
    required this.tracked,
    required this.onTap,
    this.compact = false,
    this.focusNode,
  });

  @override
  State<DetailTrackerPill> createState() => _DetailTrackerPillState();
}

class _DetailTrackerPillState extends State<DetailTrackerPill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    // widget.accent is Trakt red or Simkl cyan — a third party's mark, never
    // themed. Only the surface around it follows the theme.
    final accent = widget.accent;
    final tracked = widget.tracked;
    final radius = t.brBtn;
    return DetailFocusRing(
      focused: _focused,
      radius: radius,
      child: Material(
        color: tracked ? accent.withValues(alpha: 0.12) : t.ghostFill,
        borderRadius: radius,
        child: InkWell(
          focusNode: widget.focusNode,
          borderRadius: radius,
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            padding: widget.compact
                ? const EdgeInsets.fromLTRB(6, 7, 12, 7)
                : const EdgeInsets.fromLTRB(10, 7, 14, 7),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: tracked ? accent.withValues(alpha: 0.42) : t.ghostBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.mark,
                SizedBox(width: widget.compact ? 7 : 9),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.compact) ...[
                      Text(
                        widget.brand,
                        style: TextStyle(
                          color: tracked ? accent : t.tx3,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      widget.state,
                      style: TextStyle(
                        color: tracked ? t.tx : t.tx2,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ],
                ),
                if (widget.rating != null) ...[
                  const SizedBox(width: 9),
                  Container(
                    height: 18,
                    width: 1,
                    color: accent.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.rating}',
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
