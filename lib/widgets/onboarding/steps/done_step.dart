import 'package:flutter/material.dart';

import '../../../theme/widgets/parallax_focus.dart';
import '../onboarding_focus.dart';
import '../onboarding_models.dart';
import '../onboarding_stage.dart';

class DoneStep extends StatelessWidget {
  const DoneStep({
    super.key,
    required this.focusController,
    required this.summary,
    required this.onStart,
  });

  final OnboardFocusController focusController;
  final OnboardSummary summary;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, String value, bool skipped})>[
      (
        label: 'Debrid services',
        value: summary.services.isEmpty
            ? 'Skipped'
            : summary.services.join(', '),
        skipped: summary.services.isEmpty,
      ),
      (
        label: 'Search engines',
        value: summary.engines.isEmpty
            ? 'Skipped'
            : '${summary.engines.length} imported',
        skipped: summary.engines.isEmpty,
      ),
      (
        label: 'Trackers',
        value: summary.trackers.isEmpty
            ? 'Skipped'
            : summary.trackers.join(', '),
        skipped: summary.trackers.isEmpty,
      ),
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 65,
              height: 65,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x2434D399),
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 37,
                color: Color(0xFF34D399),
              ),
            ),
            const SizedBox(height: 18),
            for (final row in rows) _SummaryRow(row: row),
          ],
        ),
      ),
    );
  }

  Widget buildFooter(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: OnboardFocusable(
        controller: focusController,
        cell: const OnboardCell(0, 0),
        onActivate: onStart,
        shape: ParallaxShape.pill,
        radius: BorderRadius.circular(18),
        builder: (context, focused) => OnboardPillSurface(
          focused: focused,
          label: 'Start watching  ›',
          primary: true,
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.row});

  final ({String label, String value, bool skipped}) row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.onSurface.withValues(alpha: 0.07)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          Flexible(
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: row.skipped
                    ? scheme.onSurface.withValues(alpha: 0.38)
                    : const Color(0xFF34D399),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
