import 'package:flutter/material.dart';

/// Shared chrome for a tracker sheet: the brand lockup, the title it applies
/// to, and a hairline progress line while an action is in flight.
///
/// Only the chrome is shared — the two sheets' bodies stay fully independent,
/// per the "no shared type between the trackers" rule this screen follows.
class _TrackerSheetHeader extends StatelessWidget {
  final Widget mark;
  final String brand;
  final String title;
  final Color accent;
  final bool busy;

  const _TrackerSheetHeader({
    required this.mark,
    required this.brand,
    required this.title,
    required this.accent,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.centerRight,
              colors: [accent.withValues(alpha: 0.18), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              mark,
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      brand,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 2,
          child: busy
              ? LinearProgressIndicator(
                  minHeight: 2,
                  color: accent,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                )
              : Container(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ],
    );
  }
}

typedef MergedTrackerSheetHeader = _TrackerSheetHeader;

const mergedTrackerSheetHeaderConstructor = _TrackerSheetHeader.new;
