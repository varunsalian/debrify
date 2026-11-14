// Turns stored reminders into the alerts the device schedules.
//
// Application layer, pure: no clock, storage or platform access, so every
// timing rule here is testable with plain values.
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/models/sports_reminder.dart';

/// How long before kick-off the alert fires.
const sportsReminderLead = Duration(minutes: 15);

/// iOS keeps at most 64 pending notifications per app; stay under it and
/// schedule the soonest. Later ones are scheduled as earlier ones fire and
/// the app re-plans.
const sportsReminderMaxScheduled = 60;

/// A reminder is kept this long after kick-off, so a delayed start that the
/// board has not caught up with yet can still move it.
const sportsReminderRetention = Duration(hours: 6);

/// Whether a reminder for [event] can still fire before kick-off.
bool sportsReminderAvailable(SportsEvent event, DateTime now) =>
    event.status == SportsEventStatus.scheduled &&
    event.start.isAfter(now.toUtc().add(sportsReminderLead));

/// Drops reminders whose game is long over.
List<SportsReminder> sportsRemindersStillDue(
  Iterable<SportsReminder> reminders,
  DateTime now,
) {
  final cutoff = now.toUtc().subtract(sportsReminderRetention);
  return [
    for (final reminder in reminders)
      if (reminder.start.isAfter(cutoff)) reminder,
  ];
}

/// The soonest [sportsReminderMaxScheduled] alerts whose fire time is still
/// ahead, in firing order.
List<SportsReminderAlert> planSportsReminderAlerts(
  Iterable<SportsReminder> reminders,
  DateTime now,
) {
  final utcNow = now.toUtc();
  final alerts = <SportsReminderAlert>[
    for (final reminder in reminders)
      if (reminder.start.subtract(sportsReminderLead).isAfter(utcNow))
        SportsReminderAlert(
          id: reminder.eventKey,
          fireAt: reminder.start.subtract(sportsReminderLead),
          title: reminder.title,
          body: [
            'Starts in ${sportsReminderLead.inMinutes} minutes',
            if (reminder.league.isNotEmpty) reminder.league,
          ].join(' · '),
        ),
  ]..sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return alerts.length <= sportsReminderMaxScheduled
      ? alerts
      : alerts.sublist(0, sportsReminderMaxScheduled);
}

/// [reminders] updated from the board's latest [events]: a moved kick-off
/// moves its reminder, a postponed or finished game drops it. Games the
/// board did not load are left alone. Null when nothing changed.
List<SportsReminder>? reconcileSportsReminders(
  List<SportsReminder> reminders,
  Iterable<SportsEvent> events,
) {
  if (reminders.isEmpty) return null;
  final byKey = {
    for (final event in events) SportsReminder.keyOf(event): event,
  };
  var changed = false;
  final next = <SportsReminder>[];
  for (final reminder in reminders) {
    final event = byKey[reminder.eventKey];
    if (event == null) {
      next.add(reminder);
      continue;
    }
    if (event.status == SportsEventStatus.postponed ||
        event.status == SportsEventStatus.finished) {
      changed = true;
      continue;
    }
    final start = event.start.toUtc();
    if (start != reminder.start || event.displayTitle != reminder.title) {
      changed = true;
      next.add(reminder.copyWith(start: start, title: event.displayTitle));
    } else {
      next.add(reminder);
    }
  }
  return changed ? next : null;
}
