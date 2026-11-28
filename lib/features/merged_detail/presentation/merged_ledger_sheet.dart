import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/features/ledger/models/ledger_title.dart';
import 'package:debrify/features/merged_detail/presentation/merged_sheet_action_row.dart';
import 'package:debrify/features/merged_detail/presentation/merged_sheet_group_label.dart';
import 'package:debrify/features/merged_detail/presentation/merged_sheet_rating_strip.dart';
import 'package:debrify/features/merged_detail/presentation/merged_sheet_switch_row.dart';
import 'package:debrify/features/merged_detail/presentation/merged_tracker_sheet_header.dart';
import 'package:debrify/widgets/tracker_brand_marks.dart';
import 'package:flutter/material.dart';

/// The tracker's sheet on a detail page: Plan to Watch, Completed and Dropped
/// as independent switches (the tracker keeps them separately, unlike Simkl's
/// one exclusive list), a rating strip and Clear watch progress.
///
/// It stays open after a change. The host owns the state: it passes the
/// status the tracker holds and re-reads it after each change, so the
/// switches show the truth rather than an optimistic guess.
class MergedLedgerSheet extends StatelessWidget {
  const MergedLedgerSheet({
    super.key,
    required this.title,
    required this.isSeries,
    required this.isTelevision,
    required this.status,
    required this.busy,
    required this.onPlanned,
    required this.onCompleted,
    required this.onDropped,
    required this.onRate,
    required this.onClearProgress,
  });

  final String title;
  final bool isSeries;
  final bool isTelevision;
  final LedgerTitleStatus status;

  /// A change is being sent, or the status is still loading.
  final bool busy;
  final void Function(bool planned) onPlanned;
  final void Function(bool completed) onCompleted;
  final void Function(bool dropped) onDropped;

  /// A null rating removes it.
  final void Function(int? rating) onRate;
  final VoidCallback onClearProgress;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MergedTrackerSheetHeader(
              mark: const LedgerMark(size: 30),
              brand: kLedgerDisplayName,
              title: title,
              accent: kLedgerAccent,
              busy: busy,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const MergedSheetGroupLabel('Status'),
                    MergedSheetSwitchRow(
                      icon: Icons.bookmark_add_rounded,
                      label: 'Plan to Watch',
                      subtitle: status.planned
                          ? 'On your watchlist'
                          : 'Add to your watchlist',
                      value: status.planned,
                      accent: kLedgerAccent,
                      autofocus: isTelevision,
                      onTap: () => onPlanned(!status.planned),
                    ),
                    MergedSheetSwitchRow(
                      icon: Icons.check_circle_rounded,
                      label: 'Completed',
                      subtitle: status.completed
                          ? 'Turn off to remove every play'
                          : isSeries
                          ? 'Mark every aired episode watched'
                          : 'Mark watched',
                      value: status.completed,
                      accent: kLedgerAccent,
                      onTap: () => onCompleted(!status.completed),
                    ),
                    MergedSheetSwitchRow(
                      icon: Icons.cancel_rounded,
                      label: 'Dropped',
                      subtitle: status.dropped
                          ? 'Kept out of Up Next'
                          : 'Stop following and hide from Up Next',
                      value: status.dropped,
                      accent: kLedgerAccent,
                      onTap: () => onDropped(!status.dropped),
                    ),
                    const MergedSheetGroupLabel('Rating'),
                    MergedSheetRatingStrip(
                      rating: status.rating,
                      accent: kLedgerAccent,
                      onAccent: kLedgerOnAccent,
                      onRate: onRate,
                      onClear: status.rating == null
                          ? null
                          : () => onRate(null),
                    ),
                    MergedSheetActionRow(
                      icon: Icons.restart_alt_rounded,
                      label: 'Clear watch progress on $kLedgerDisplayName',
                      description:
                          'Clear watched history and resume progress on '
                          '$kLedgerDisplayName only. Local progress and other '
                          'trackers are kept.',
                      onTap: onClearProgress,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
