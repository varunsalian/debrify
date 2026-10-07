import 'package:flutter/material.dart';

String iptvAutoRefreshLabel(int hours) =>
    hours == 0 ? 'Off' : 'Every $hours hours';

const iptvAutoRefreshExplanation =
    'Updates occur when the app or operating system permits; exact timing '
    'is not guaranteed. Local files are not refreshed.';

/// Shared picker for phone and TV settings, including keyboard/DPAD input.
class IptvAutoRefreshDialog extends StatelessWidget {
  const IptvAutoRefreshDialog({super.key, required this.intervalHours});

  final int intervalHours;

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: const Text('Auto-refresh'),
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Text(
          'Applies to all sources in this profile. '
          '$iptvAutoRefreshExplanation',
        ),
      ),
      for (final hours in const [0, 6, 12, 24, 48])
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          autofocus: hours == intervalHours,
          onPressed: () => Navigator.of(context).pop(hours),
          child: Row(
            children: [
              Icon(
                hours == intervalHours
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              const SizedBox(width: 12),
              Text(iptvAutoRefreshLabel(hours)),
            ],
          ),
        ),
    ],
  );
}
