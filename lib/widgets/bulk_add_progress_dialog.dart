import 'package:flutter/material.dart';

import '../models/torrent.dart';
import '../utils/dialog_tap_guard.dart';

/// Shared progress dialog for bulk-adding torrents to a debrid provider.
///
/// Reproduces Home's per-provider bulk-add dialog exactly (linear progress bar
/// + Success / Failed / Skipped chips + a scrolling per-torrent status list +
/// Cancel), but as one parameterized controller so the Search tab shows the
/// identical experience for all five providers without five near-duplicate
/// inline dialogs.
///
/// Lifecycle: [show] pushes the dialog and returns the controller. The caller
/// mutates counters/status through [update] (which rebuilds the dialog), reads
/// [cancelled] at loop boundaries, and calls [close] exactly once on
/// completion. [close] is idempotent — the Cancel button also calls it — so the
/// dialog is popped once and never double-pops the route underneath.
class BulkAddProgressController {
  final BuildContext _context;
  final Color accent;
  final Color notCachedColor;
  final IconData titleIcon;
  final String title;
  final bool showSkipped;
  final String successChipLabel;
  final String skippedChipLabel;
  final String notCachedSubtitle;
  final List<Torrent> torrents;

  int total;
  int current = 0;
  int success = 0;
  int failure = 0;
  int skipped = 0;
  bool cancelled = false;
  bool _closed = false;
  StateSetter? _setDialogState;

  /// infohash -> pending | processing | success | error | not_cached
  final Map<String, String> status = {};

  BulkAddProgressController._({
    required BuildContext context,
    required this.accent,
    required this.notCachedColor,
    required this.titleIcon,
    required this.title,
    required this.showSkipped,
    required this.successChipLabel,
    required this.skippedChipLabel,
    required this.notCachedSubtitle,
    required this.torrents,
    required this.total,
  }) : _context = context {
    for (final t in torrents) {
      status[t.infohash] = 'pending';
    }
  }

  static BulkAddProgressController show(
    BuildContext context, {
    required Color accent,
    required IconData titleIcon,
    required String title,
    required List<Torrent> torrents,
    required int total,
    Color notCachedColor = const Color(0xFFF59E0B),
    bool showSkipped = false,
    String successChipLabel = 'Success',
    String skippedChipLabel = 'Not cached',
    String notCachedSubtitle = 'Not cached',
    Map<String, String>? initialStatus,
    int initialSkipped = 0,
  }) {
    final controller = BulkAddProgressController._(
      context: context,
      accent: accent,
      notCachedColor: notCachedColor,
      titleIcon: titleIcon,
      title: title,
      showSkipped: showSkipped,
      successChipLabel: successChipLabel,
      skippedChipLabel: skippedChipLabel,
      notCachedSubtitle: notCachedSubtitle,
      torrents: torrents,
      total: total,
    );
    if (initialStatus != null) controller.status.addAll(initialStatus);
    controller.skipped = initialSkipped;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            controller._setDialogState = setState;
            return controller._build();
          },
        );
      },
    );
    return controller;
  }

  /// Apply a mutation to the counters/status map and rebuild the dialog.
  void update(void Function() mutate) {
    mutate();
    if (_closed) return;
    try {
      _setDialogState?.call(() {});
    } catch (_) {}
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (!_context.mounted) return;
    final nav = Navigator.of(_context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
  }

  Widget _build() {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(titleIcon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: total > 0 ? current / total : (showSkipped ? 1.0 : 0.0),
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
            const SizedBox(height: 12),
            Text(
              'Progress: $current of $total',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip(Icons.check_circle, const Color(0xFF10B981),
                    '$successChipLabel: $success'),
                _chip(Icons.error, const Color(0xFFEF4444),
                    'Failed: $failure'),
                if (showSkipped)
                  _chip(Icons.block, const Color(0xFFF59E0B),
                      '$skippedChipLabel: $skipped'),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: torrents.length,
                itemBuilder: (context, index) {
                  final torrent = torrents[index];
                  final st = status[torrent.infohash] ?? 'pending';

                  IconData icon;
                  Color iconColor;
                  String? subtitle;

                  if (st == 'success') {
                    icon = Icons.check_circle;
                    iconColor = const Color(0xFF10B981);
                  } else if (st == 'error') {
                    icon = Icons.error;
                    iconColor = const Color(0xFFEF4444);
                  } else if (st == 'not_cached') {
                    icon = Icons.cancel;
                    iconColor = notCachedColor;
                    subtitle = notCachedSubtitle;
                  } else if (st == 'processing') {
                    icon = Icons.hourglass_empty;
                    iconColor = accent;
                  } else {
                    icon = Icons.circle_outlined;
                    iconColor = Colors.white54;
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(icon, color: iconColor, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                torrent.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                              if (subtitle != null)
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    color: iconColor.withValues(alpha: 0.7),
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () {
            DialogTapGuard.markKeyAction();
            cancelled = true;
            close();
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _chip(IconData icon, Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
