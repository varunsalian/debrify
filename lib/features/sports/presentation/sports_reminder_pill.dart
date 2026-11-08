// The "Remind me" control in a game's details.
//
// Presentation layer: renders the reminder state and dispatches the toggle.
// The details route receives the state as a snapshot, so the pill keeps its
// own copy and updates it from each toggle's outcome.
import 'package:debrify/features/sports/application/sports_reminder_plan.dart';
import 'package:debrify/features/sports/application/sports_reminders_notifier.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;

/// Shown when the system refuses notification permission.
const sportsReminderPermissionCopy =
    'Notifications are off for Debrify. Turn them on in system settings to '
    'get kick-off reminders.';

/// Shown when the reminder could not be saved.
const sportsReminderFailedCopy = "Couldn't save the reminder. Try again.";

/// Shown when kick-off is too close for the reminder to fire before it.
const sportsReminderTooLateCopy = 'Kick-off is too close for a reminder now.';

/// What the details route needs to show and flip one game's reminder.
typedef SportsReminderControl = ({
  bool on,
  Future<SportsReminderToggle> Function() toggle,
});

class SportsReminderPill extends StatefulWidget {
  const SportsReminderPill({
    super.key,
    required this.control,
    this.autofocus = false,
  });

  final SportsReminderControl control;
  final bool autofocus;

  @override
  State<SportsReminderPill> createState() => _SportsReminderPillState();
}

class _SportsReminderPillState extends State<SportsReminderPill> {
  late bool _on = widget.control.on;
  bool _busy = false;
  String? _message;

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    SportsReminderToggle outcome;
    try {
      outcome = await widget.control.toggle();
    } catch (_) {
      outcome = SportsReminderToggle.failed;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (outcome) {
        case SportsReminderToggle.added:
          _on = true;
        case SportsReminderToggle.removed:
          _on = false;
        case SportsReminderToggle.permissionDenied:
          _message = sportsReminderPermissionCopy;
        case SportsReminderToggle.unavailable:
          _message = sportsReminderTooLateCopy;
        case SportsReminderToggle.failed:
          _message = sportsReminderFailedCopy;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final minutes = sportsReminderLead.inMinutes;
    final text = _on
        ? 'Reminder set · $minutes min before'
        : 'Remind me $minutes min before';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SportsFocusPill.row(
          key: const ValueKey('sports-details-reminder'),
          label: text,
          selected: _on,
          toggled: _on,
          autofocus: widget.autofocus,
          onPressed: _toggle,
          builder: (_, ink, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _on
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                size: 17,
                color: ink,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: sportsLabelText(
                  text,
                  ink,
                  weight: FontWeight.w700,
                  ellipsize: true,
                ),
              ),
            ],
          ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: sportsLabelText(
              _message!,
              _tokens.fgDim,
              size: 12,
              height: 1.4,
              maxLines: 3,
            ),
          ),
      ],
    );
  }
}
