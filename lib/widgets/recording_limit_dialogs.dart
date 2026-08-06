import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/settings/recordings_page.dart';
import '../services/live_recording_service.dart';
import '../services/recording_capacity.dart';

/// The two dialogs of the simultaneous-recordings limit, shared by settings
/// and by every record/schedule entry point:
///  - [showRecordingLimitPicker]: choose the limit, with the honest warning.
///  - [ensureRecordingCapacity]: the pre-flight gate — detects a conflict,
///    names what's in the way, and offers the two real resolutions (raise
///    the limit / manage recordings) before retrying the check.

const _kRec = Color(0xFFF43F5E);

/// Limit picker (1..[LiveRecordingService.maxConcurrentCeiling]). Returns
/// the newly-saved value, or null when dismissed. Persists on selection.
Future<int?> showRecordingLimitPicker(BuildContext context) async {
  final current = await LiveRecordingService.maxConcurrent();
  if (!context.mounted) return null;
  final picked = await showDialog<int>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Simultaneous recordings'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Text(
            'Every recording is an extra connection to your provider, on '
            'top of what you\'re watching. Many IPTV accounts allow only '
            '1–3 connections — set more than yours allows and the provider '
            'may block streams; parallel recordings also strain the '
            'network and the box.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Theme.of(dialogContext)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
        ),
        for (var n = 1; n <= LiveRecordingService.maxConcurrentCeiling; n++)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(n),
            child: Row(
              children: [
                Text(
                  '$n',
                  style: TextStyle(
                    fontWeight:
                        n == current ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    switch (n) {
                      1 => 'one at a time — safest',
                      2 => 'default',
                      _ => 'needs a provider plan with $n+ connections',
                    },
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(dialogContext)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ),
                if (n == current)
                  const Icon(Icons.check_rounded, size: 18),
              ],
            ),
          ),
      ],
    ),
  );
  if (picked == null) return null;
  await LiveRecordingService.setMaxConcurrent(picked);
  return picked;
}

/// Pre-flight capacity gate for a record/schedule attempt. Returns true when
/// the caller should proceed.
///
/// Pass [startMs]/[endMs] for schedules; omit both for record-now. When a
/// conflict exists, the dialog names the occupying recordings and offers:
///  - Raise limit → the picker (warning included), then re-check;
///  - Manage → the Recordings hub (hidden when [offerManage] is false —
///    e.g. the hub's own manual flow, where the rows are right behind the
///    dialog), then re-check;
///  - Cancel.
Future<bool> ensureRecordingCapacity(
  BuildContext context, {
  int? startMs,
  int? endMs,
  String? candidateUrl,
  bool offerManage = true,
}) async {
  assert((startMs == null) == (endMs == null));
  Future<RecordingCapacityConflict?> check() => startMs != null
      ? checkScheduleCapacity(
          startMs: startMs,
          endMs: endMs!,
          candidateUrl: candidateUrl,
        )
      : checkRecordNowCapacity();

  var conflict = await check();
  while (conflict != null) {
    if (!context.mounted) return false;
    final choice = await _showConflictDialog(
      context,
      conflict,
      isSchedule: startMs != null,
      offerManage: offerManage,
    );
    if (!context.mounted) return false;
    switch (choice) {
      case _ConflictChoice.cancel:
        return false;
      case _ConflictChoice.raiseLimit:
        await showRecordingLimitPicker(context);
      case _ConflictChoice.manage:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const RecordingsPage()),
        );
    }
    if (!context.mounted) return false;
    conflict = await check();
  }
  return true;
}

enum _ConflictChoice { cancel, raiseLimit, manage }

Future<_ConflictChoice> _showConflictDialog(
  BuildContext context,
  RecordingCapacityConflict conflict, {
  required bool isSchedule,
  required bool offerManage,
}) async {
  final names = conflict.busyLabels.take(4).join(' · ');
  final more = conflict.busyLabels.length - 4;
  final choice = await showDialog<_ConflictChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF14141D),
      title: const Row(
        children: [
          Icon(Icons.fiber_manual_record_rounded, color: _kRec, size: 16),
          SizedBox(width: 8),
          Text(
            'Recording conflict',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: Text(
        '${isSchedule ? 'This would need more simultaneous recordings than '
                'the limit allows' : 'The recording limit is already in '
                'use'} (${conflict.limit} at a time).\n\n'
        'In the way: $names${more > 0 ? ' and $more more' : ''}.\n\n'
        'Raise the limit only if your provider allows that many '
        'connections — or free a slot by stopping/cancelling one.',
        style: const TextStyle(color: Colors.white70, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_ConflictChoice.cancel),
          child: const Text('Cancel'),
        ),
        if (offerManage)
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ConflictChoice.manage),
            child: const Text('Manage recordings'),
          ),
        TextButton(
          autofocus: true,
          onPressed: () =>
              Navigator.of(dialogContext).pop(_ConflictChoice.raiseLimit),
          child: const Text('Raise limit'),
        ),
      ],
    ),
  );
  return choice ?? _ConflictChoice.cancel;
}
