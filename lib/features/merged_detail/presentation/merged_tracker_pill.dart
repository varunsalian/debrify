import 'package:debrify/features/merged_detail/presentation/merged_focus_halo.dart';
import 'package:flutter/material.dart';

/// A tracker's identity in the action row: its brand mark, its name, and the
/// live relationship it holds to this title, in one control that opens that
/// tracker's sheet.
///
/// This replaces the pair of anonymous round icon buttons *and* the status
/// chip rows under the title — the chips rendered exactly the state these
/// pills now carry, so the hero showed every fact twice.
///
/// [tracked] drives the two forms: brand-tinted when the tracker holds the
/// title, plain outline when it doesn't (and while the status loads, so the
/// row keeps its geometry).
class _TrackerPill extends StatefulWidget {
  final Widget mark;

  /// Short brand name, drawn as the pill's uppercase eyebrow.
  final String brand;

  /// The live state line — "Watchlist · Collected", "Watching", "Not tracked".
  final String state;

  /// 1–10 tracker rating, shown in its own compartment when set.
  final int? rating;

  /// The tracker's brand colour, used for the tint, border and rating.
  final Color accent;
  final bool tracked;
  final String tooltip;
  final VoidCallback onTap;

  const _TrackerPill({
    required this.mark,
    required this.brand,
    required this.state,
    required this.rating,
    required this.accent,
    required this.tracked,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_TrackerPill> createState() => _TrackerPillState();
}

class _TrackerPillState extends State<_TrackerPill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final tracked = widget.tracked;
    final radius = BorderRadius.circular(999);
    final pill = MergedFocusHalo(
      focused: _focused,
      radius: radius,
      child: Material(
        color: tracked
            ? accent.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 8, 15, 8),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: tracked
                    ? accent.withValues(alpha: 0.42)
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.mark,
                const SizedBox(width: 9),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.brand,
                      style: TextStyle(
                        color: tracked
                            ? accent
                            : Colors.white.withValues(alpha: 0.5),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.state,
                      style: TextStyle(
                        color: tracked
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.62),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ],
                ),
                if (widget.rating != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    height: 20,
                    width: 1,
                    color: accent.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    '${widget.rating}',
                    style: TextStyle(
                      color: accent,
                      fontSize: 12.5,
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
    return Tooltip(message: widget.tooltip, child: pill);
  }
}

typedef MergedTrackerPill = _TrackerPill;

const mergedTrackerPillConstructor = _TrackerPill.new;
