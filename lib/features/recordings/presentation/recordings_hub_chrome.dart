import 'package:debrify/features/recordings/presentation/recordings_hub_buttons.dart';
import 'package:debrify/features/recordings/presentation/recordings_hub_tokens.dart';
import 'package:flutter/material.dart';

// ── Top bar ─────────────────────────────────────────────────────────────────
class _HubBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onSchedule;

  /// Non-null exactly when no focusable row sits between the hub bar and
  /// the library — the state where geometric DOWN would hit a delete icon.
  final VoidCallback? onScheduleDown;

  const _HubBar({
    required this.onBack,
    required this.onSchedule,
    this.onScheduleDown,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 20, 10),
      child: Row(
        children: [
          RecordingsHubHubIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onPressed: onBack,
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.fiber_manual_record_rounded,
            color: kRecordingsHubRec,
            size: 16,
          ),
          const SizedBox(width: 8),
          const Text(
            'Recordings',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          RecordingsHubHubButton(
            icon: Icons.add_rounded,
            label: 'Schedule',
            filled: true,
            onPressed: onSchedule,
            onDown: onScheduleDown,
          ),
        ],
      ),
    );
  }
}

typedef RecordingsHubHubBar = _HubBar;

// ── Sections ────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  final String? chip;
  final Color chipColor;
  final Widget? action;
  const _SectionHeader({
    required this.label,
    this.chip,
    required this.chipColor,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 0, 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
          if (chip != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: chipColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                chip!,
                style: TextStyle(
                  color: chipColor == Colors.white38
                      ? Colors.white.withValues(alpha: 0.55)
                      : chipColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}

typedef RecordingsHubSectionHeader = _SectionHeader;

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 12.5,
          height: 1.45,
        ),
      ),
    );
  }
}

typedef RecordingsHubEmptyHint = _EmptyHint;
