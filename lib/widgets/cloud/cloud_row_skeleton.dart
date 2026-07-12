import 'package:flutter/material.dart';

import '../skeleton_poster.dart';

/// Static placeholder rows shown while a cloud folder listing loads — shaped
/// like a `CloudFileRow` (icon chip + title/meta bars) so the swap to real
/// rows doesn't reflow. Non-interactive, non-scrolling, static (see
/// [ShimmerBox] for why nothing animates during a load).
class CloudRowSkeletonList extends StatelessWidget {
  final int rows;

  /// Must match the padding of the ListView the skeleton stands in for, so
  /// the swap to real rows doesn't jump.
  final EdgeInsetsGeometry padding;

  const CloudRowSkeletonList({
    super.key,
    this.rows = 9,
    this.padding = const EdgeInsets.all(16),
  });

  // Slightly varied title widths so the column doesn't look rubber-stamped.
  static const _titleFractions = [
    0.62, 0.45, 0.55, 0.38, 0.58, 0.42, 0.50, 0.35, 0.60,
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows,
      itemBuilder: (context, i) {
        final frac = _titleFractions[i % _titleFractions.length];
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 13),
          child: Row(
            children: [
              const SizedBox(
                width: 34,
                height: 34,
                child: ShimmerBox(radius: 9),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: frac,
                      child: const SizedBox(
                        height: 13,
                        child: ShimmerBox(radius: 4),
                      ),
                    ),
                    const SizedBox(height: 7),
                    const FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: 0.28,
                      child: SizedBox(
                        height: 10,
                        child: ShimmerBox(radius: 4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
